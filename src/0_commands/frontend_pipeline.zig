const std = @import("std");

const sf = @import("../1_base/source_files.zig");
const source_db = @import("../1_base/source_db.zig");
const diag = @import("../1_base/diagnostic.zig");
const token = @import("../2_tokens/token.zig");
const tokenizer = @import("../2_tokens/tokenizer.zig");
const st = @import("../3_syntax/syntax_tree.zig");
const st_print = @import("../3_syntax/syntax_tree_print.zig");
const syntaxer = @import("../3_syntax/syntaxer.zig");
pub const cache = @import("frontend_cache.zig");
const module_sg = @import("../4_semantics/module/graph.zig");
const module_semantizer = @import("../4_semantics/module/semantizer.zig");
const global_sg = @import("../4_semantics/global/graph.zig");
const global_semantizer = @import("../4_semantics/global/semantizer.zig");
const global_once_verify = @import("../4_semantics/global/once_verify.zig");
const module_test_declaration_verify = @import("../4_semantics/module/test_declaration_verify.zig");
const global_safety_checker = @import("../4_semantics/safety/checker.zig");

pub const FrontendPipeline = struct {
    pub const SemantizingOptions = struct {
        include_tests: bool = false,
        selected_test_name: ?[]const u8 = null,
        implicit_testing_module_dir: ?[]const u8 = null,
        exhaustive_function_bodies: bool = false,
        root_selection: global_semantizer.RootSelection = .program,
    };

    pub const Options = struct {
        target: @import("../1_base/target.zig").Config = .{},
        semantizing: SemantizingOptions = .{},
        collect_stats: bool = false,
        module_jobs: usize = 1,
        entry_module_dir: ?[]const u8 = null,
        module_cache: ?*cache.ModuleCache = null,
    };

    allocator: std.mem.Allocator,
    io: std.Io,
    diagnostics: *diag.Diagnostics,
    options: Options,
    source_db: *const source_db.SourceDb,
    syntax_files: std.array_list.Managed(st.FileSyntaxTree),
    // Borrow original source buffers; rendered selections never replace the
    // source database. Computed decisions survive tokenization for the loader.
    source_selections: std.ArrayList(@import("../1_base/target_selection.zig").Prepared) = .empty,
    syntax_root_list: std.array_list.Managed(st.SyntaxRef),
    module_graphs: std.ArrayList(module_sg.ModuleSemanticGraph) = .empty,
    module_entries: std.ArrayList(*cache.ModuleCache.Entry) = .empty,
    module_arenas: std.ArrayList(std.heap.ArenaAllocator) = .empty,
    module_cache_hits: usize = 0,
    module_cache_misses: usize = 0,
    tokenizing_ns: u64 = 0,
    syntaxing_ns: u64 = 0,
    /// Authoritative whole-program semantic artifact. No pointer SemanticGraph
    /// can be materialized by this pipeline anymore.
    global_graph: ?global_sg.GlobalSemanticGraph = null,
    global_stats: global_semantizer.Stats = .{},
    global_safety_stats: global_safety_checker.SafetyChecker.Stats = .{},
    safety_ctx: ?global_safety_checker.SafetyChecker = null,
    safety_ns: u64 = 0,
    module_semantizing_ns: u64 = 0,
    global_semantic_ns: u64 = 0,
    module_lowered_functions: u32 = 0,
    syntax_node_count: usize = 0,
    entry_source: ?[]const u8 = null,
    entry_path: ?[]const u8 = null,
    entry_file: ?source_db.FileId = null,
    staged_arena: ?*std.heap.ArenaAllocator = null,
    prepared_session: ?*global_semantizer.Session = null,
    deferred_entry: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        diagnostics: *diag.Diagnostics,
        options: Options,
    ) FrontendPipeline {
        return .{
            .allocator = allocator,
            .io = io,
            .diagnostics = diagnostics,
            .options = options,
            .source_db = &diagnostics.source_db,
            .syntax_files = std.array_list.Managed(st.FileSyntaxTree).init(allocator),
            .syntax_root_list = std.array_list.Managed(st.SyntaxRef).init(allocator),
        };
    }

    pub fn deinit(self: *FrontendPipeline) void {
        self.clearModuleGraphs();
        self.module_graphs.deinit(self.allocator);
        self.module_entries.deinit(self.allocator);
        self.module_arenas.deinit(self.allocator);
        for (self.syntax_files.items) |*file| file.deinit(self.allocator);
        self.syntax_files.deinit();
        for (self.source_selections.items) |*selection| selection.deinit(self.allocator);
        self.source_selections.deinit(self.allocator);
        self.syntax_root_list.deinit();
        if (self.entry_source) |value| self.allocator.free(value);
        if (self.entry_path) |value| self.allocator.free(value);
    }

    pub fn tokenizeFiles(self: *FrontendPipeline, files: []const sf.SourceFile) !void {
        self.clearModuleGraphs();
        for (self.syntax_files.items) |*file| file.deinit(self.allocator);
        self.syntax_files.clearRetainingCapacity();
        for (self.source_selections.items) |*selection| selection.deinit(self.allocator);
        self.source_selections.clearRetainingCapacity();
        try self.syntax_files.ensureTotalCapacity(files.len);
        try self.source_selections.ensureTotalCapacity(self.allocator, files.len);

        for (files, 0..) |source_file, index| {
            var error_offset: usize = 0;
            var prepared = @import("../1_base/target_selection.zig").Prepared.init(self.allocator, source_file.code, self.options.target, &error_offset, .computed) catch |err| {
                if (err == error.OutOfMemory) return err;
                try self.diagnostics.add(.{ .file = self.source_db.fileId(index), .offset = @intCast(error_offset) }, .syntax, "invalid target selection: {s}", .{@import("../1_base/target_selection.zig").errorMessage(err)});
                return err;
            };
            errdefer prepared.deinit(self.allocator);
            const selected = try prepared.syntax(self.allocator);
            defer selected.deinit(self.allocator);
            var tokenizer_ctx = tokenizer.Tokenizer.init(
                self.allocator,
                self.diagnostics,
                selected.source,
                self.source_db.fileId(index),
            );
            defer tokenizer_ctx.deinit();
            _ = try tokenizer_ctx.tokenize();
            var file = st.FileSyntaxTree.initOwnedTokens(self.source_db.fileId(index), tokenizer_ctx.takeTokens());
            errdefer file.deinit(self.allocator);
            self.syntax_files.appendAssumeCapacity(file);
            self.source_selections.appendAssumeCapacity(prepared);
        }
    }

    pub fn syntax(self: *FrontendPipeline) ![]const st.SyntaxRef {
        self.syntax_root_list.clearRetainingCapacity();
        self.syntax_node_count = 0;
        for (self.syntax_files.items) |*file| {
            const file_id = file.file_id;
            var syntax_ctx = syntaxer.Syntaxer.initFile(self.allocator, file.*, self.source_db.get(file_id).source, self.diagnostics);
            file.* = .{ .file_id = file_id };
            file.* = syntax_ctx.parse() catch |err| {
                file.* = syntax_ctx.file;
                syntax_ctx.file = .{ .file_id = file_id };
                return err;
            };
            self.syntax_node_count += file.nodes.len;
            for (file.roots) |node| try self.syntax_root_list.append(file.ref(node));
        }
        return self.syntax_root_list.items;
    }

    pub fn printSyntaxTrees(self: *const FrontendPipeline) void {
        std.debug.print("\nSYNTAX TREE\n", .{});
        for (self.syntax_files.items) |*file| {
            for (file.roots) |node| st_print.printNode(file, self.source_db, node, 0);
        }
        std.debug.print("\n", .{});
    }

    pub fn syntaxStorageMetrics(self: *const FrontendPipeline) st.FileSyntaxTree.StorageMetrics {
        var result = st.FileSyntaxTree.StorageMetrics{ .token_bytes = 0, .node_base_bytes = 0, .extra_data_bytes = 0, .root_bytes = 0 };
        for (self.syntax_files.items) |*file| {
            const metrics = file.storageMetrics();
            result.token_bytes += metrics.token_bytes;
            result.node_base_bytes += metrics.node_base_bytes;
            result.extra_data_bytes += metrics.extra_data_bytes;
            result.root_bytes += metrics.root_bytes;
        }
        return result;
    }

    pub fn tokenCount(self: *const FrontendPipeline) usize {
        var count: usize = 0;
        for (self.syntax_files.items) |file| count += file.tokens.len;
        return count;
    }

    pub fn tokenStorageBytes(self: *const FrontendPipeline) usize {
        return self.tokenCount() * @sizeOf(token.Token);
    }

    pub fn tokensForPath(self: *const FrontendPipeline, path: []const u8) ?token.View {
        const file_id = self.source_db.findPath(path) orelse return null;
        for (self.syntax_files.items) |*file| {
            if (file.file_id == file_id) return token.View.init(&file.tokens);
        }
        return null;
    }

    pub fn parseFiles(self: *FrontendPipeline, files: []const sf.SourceFile) ![]const st.SyntaxRef {
        const start = std.Io.Timestamp.now(self.io, .boot).nanoseconds;
        try self.tokenizeFiles(files);
        const syntax_start = std.Io.Timestamp.now(self.io, .boot).nanoseconds;
        self.tokenizing_ns = @intCast(syntax_start - start);
        const roots = try self.syntax();
        self.syntaxing_ns = @intCast(std.Io.Timestamp.now(self.io, .boot).nanoseconds - syntax_start);
        return roots;
    }

    /// Test discovery only executes closed source-selection requests. It never
    /// selects main or a test body as an executable root. Ordinary files keep
    /// the parser-only discovery path; computed declarations use the shared
    /// staged loader and retain their selected syntax for the caller.
    pub fn prepareTestDiscovery(self: *FrontendPipeline, files: []const sf.SourceFile) !void {
        if (self.options.semantizing.root_selection != .requests_only) return error.InvalidDiscoveryRootSelection;
        _ = try self.parseFiles(files);
        if (self.diagnostics.hasErrors()) return error.Reported;
        var computed = false;
        scan: for (self.syntax_files.items) |*file| for (file.roots) |root| {
            if (file.ifStatement(root)) |conditional| if (conditional.comptime_selection) {
                computed = true;
                break :scan;
            };
        };
        if (computed) {
            self.deferred_entry = false;
            try self.buildGlobalGraph();
        }
    }

    /// Prepare an immutable semantic template for persistent execution. The
    /// pipeline owns it and all borrowed source/module artifacts. Consumers
    /// fork the template; neither commands nor reset mutate its frozen choices.
    pub fn prepareSessionFiles(self: *FrontendPipeline, files: []const sf.SourceFile) !*const global_semantizer.Session {
        const previous = self.options.semantizing;
        self.options.semantizing.root_selection = .requests_only;
        self.options.semantizing.exhaustive_function_bodies = false;
        defer self.options.semantizing = previous;
        try self.prepareFiles(files, false);
        try self.buildModuleGraphs();
        const session = try self.allocator.create(global_semantizer.Session);
        errdefer self.allocator.destroy(session);
        const computed = for (self.module_graphs.items) |module| {
            if (module.conditions.items.len != 0) break true;
        } else false;
        if (computed) {
            try self.prepareStagedSession(session);
        } else {
            try session.init(self.allocator, self.module_graphs.items, .{ .target = self.options.target, .root_selection = .requests_only, .exhaustive_function_bodies = false, .diagnostics = self.diagnostics });
            errdefer session.deinit();
            try session.advance();
        }
        errdefer session.deinit();
        // An unresolved condition must fail before interactive publication.
        var publication: global_semantizer.Session = undefined;
        try session.fork(&publication, self.allocator, self.diagnostics);
        defer publication.deinit();
        var checked = try publication.finish();
        defer checked.graph.deinit(self.allocator);
        self.prepared_session = session;
        return session;
    }

    fn prepareFiles(self: *FrontendPipeline, files: []const sf.SourceFile, include_entry: bool) !void {
        _ = try self.parseFiles(files);
        // Syntax diagnostics are terminal for this compilation. Continuing into
        // ModuleSema/GlobalSema can only manufacture secondary unresolved work
        // and pollute the primary parser diagnostic with internal debug noise.
        if (self.diagnostics.hasErrors()) return error.Reported;
        try module_test_declaration_verify.validate(
            self.syntax_files.items,
            self.source_db,
            self.diagnostics,
            self.options.semantizing.include_tests,
            self.options.semantizing.selected_test_name,
        );
        var computed_module = false;
        for (self.syntax_files.items) |*file| for (file.roots) |root| {
            if (file.ifStatement(root)) |conditional| if (conditional.comptime_selection) {
                computed_module = true;
            };
        };
        self.deferred_entry = include_entry and computed_module;
        if (include_entry and !computed_module) try self.appendProgramEntry();
        try self.validateFunctionSignatures();
        try @import("../4_semantics/module/assume_verify.zig").validate(self.allocator, self.syntax_files.items, self.source_db, self.diagnostics);
        if (self.diagnostics.hasErrors()) return error.Reported;
    }

    /// Produce and safety-check the final indexed semantic graph.
    pub fn semantizeGlobalFiles(self: *FrontendPipeline, files: []const sf.SourceFile) !*const global_sg.GlobalSemanticGraph {
        try self.prepareFiles(files, true);
        try self.buildGlobalGraph();
        try self.analyzeGlobalSafety();
        // Initial source execution consumes finalized dependencies. Keep the
        // request table until this boundary so caching and specialization cannot
        // silently turn #run into an ordinary runtime call. Staged type/value
        // resolution must eventually schedule these same requests earlier.
        try @import("../execution/comptime.zig").resolve(self.allocator, &self.global_graph.?, self.diagnostics);
        return &self.global_graph.?;
    }

    // The entry template is ordinary language code in the user's module. It
    // therefore uses the same dispatch, ownership cleanup, and safety checks
    // as source functions; codegen has no resource-construction privilege.
    fn appendProgramEntry(self: *FrontendPipeline) !void {
        const dir = self.options.entry_module_dir orelse return;
        const target = self.options.semantizing.selected_test_name orelse "main";
        var found = false;
        var takes_system = false;
        var returns_status = false;
        // Bootstrap reporting only when requested. Creating FFI/terminal
        // owners in otherwise pure entries changes once and capability checks.
        var needs_reporting = self.options.semantizing.selected_test_name != null;
        for (self.syntax_files.items) |*file| for (file.tokens.items(.content), 0..) |content, token_index| {
            if (content != .triple_bang) continue;
            const offset = file.tokenLocation(@enumFromInt(token_index)).offset;
            // Retained original trees still contain module directives. Their
            // selected declarations live in separate fragment trees; only those
            // declarations can introduce entry reporting requirements.
            const deferred = for (file.roots) |root| {
                const conditional = file.ifStatement(root) orelse continue;
                if (!conditional.comptime_selection) continue;
                const file_index = @intFromEnum(file.file_id);
                if (file_index >= self.source_selections.items.len) continue;
                const selection = &self.source_selections.items[file_index];
                for (selection.plan.branches.items) |branch| {
                    if (branch.extent.start == file.location(root).offset and offset >= branch.extent.start and offset < branch.extent.end) break;
                } else continue;
                break true;
            } else false;
            if (!deferred) needs_reporting = true;
        };
        for (self.syntax_files.items) |*file| {
            const source = self.source_db.get(file.file_id);
            if (!std.mem.eql(u8, std.fs.path.dirname(source.path) orelse ".", dir)) continue;
            for (file.roots) |root| {
                const function = if (file.testDeclaration(root)) |test_decl| test_decl.function else file.functionDeclaration(root) orelse continue;
                const name = file.tokenText(self.source_db, function.name_token);
                if (std.mem.eql(u8, name, target)) {
                    found = true;
                    if (self.options.semantizing.selected_test_name == null) {
                        const output = file.structTypeLiteral(function.output) orelse return error.InvalidMainOutput;
                        if (output.fields.len == 1) {
                            const field = file.structTypeField(output.fields[0]).?;
                            returns_status = std.mem.eql(u8, file.tokenText(self.source_db, field.name_token), "status_code");
                        }
                        if (output.fields.len != 0 and !returns_status) {
                            try self.diagnostics.add(file.location(root), .semantic, "main must return no values or (.status_code: Int32)", .{});
                            return error.Reported;
                        }
                    }
                    if (file.structTypeLiteral(function.input)) |input| {
                        for (input.fields) |field_node| {
                            const field = file.structTypeField(field_node) orelse continue;
                            if (std.mem.eql(u8, file.tokenText(self.source_db, field.name_token), "system")) takes_system = true;
                        }
                    }
                }
                if (std.mem.eql(u8, name, "__argi_entry")) {
                    try self.diagnostics.add(file.location(root), .semantic, "'__argi_entry' is reserved for program entry", .{});
                    return error.Reported;
                }
            }
        }
        if (!found) return;
        const is_test = self.options.semantizing.selected_test_name != null;
        const output = if (is_test) "!()" else "(.status_code: Int32 = 0)";
        const result = if (is_test) "result" else "status_code";
        const template = if (takes_system) @embedFile("program_entry.rg") else @embedFile("plain_entry.rg");
        const tracer = if (needs_reporting)
            "trace_buffer :: [4096]UInt8 = zeroed#(.t: [4096]UInt8)()\n" ++
                "    tracer_storage ::= FixedSizeErrorTracer(.buffer = view($&trace_buffer))\n" ++
                "    tracer_virtual ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer_storage)\n" ++
                "    assume error_tracer ::= $&tracer_virtual"
        else
            "assume error_tracer ::= $&noop_error_tracer";
        const call_args = if (takes_system) ".system = system" else "";
        // Test diagnostics must finish while the entry's tracer and terminal
        // are alive. Replace the reported trace with a program-lifetime noop
        // trace before returning the unchanged reason to the C status wrapper.
        const call = if (is_test)
            try std.fmt.allocPrint(self.allocator, "test_result := {s}({s})\n" ++
                "    match test_result {{\n" ++
                "        ..ok _ {{}}\n" ++
                "        ..error $&error {{\n" ++
                "            assume error_tracer ::= $&noop_error_tracer\n" ++
                "            report_trace(.tracer = error&.tracer, .writer = $&terminal&.stderr)\n" ++
                "            error&.tracer = $&noop_error_tracer\n" ++
                "        }}\n" ++
                "    }}\n" ++
                "    result = ~test_result", .{ target, call_args })
        else if (returns_status)
            try std.fmt.allocPrint(self.allocator, "{s} = {s}({s})", .{ result, target, call_args })
        else
            try std.fmt.allocPrint(self.allocator, "__main_result ::= {s}({s})", .{ target, call_args });
        defer self.allocator.free(call);
        const with_output = try std.mem.replaceOwned(u8, self.allocator, template, "__ARGI_OUTPUT__", output);
        defer self.allocator.free(with_output);
        const with_tracer = try std.mem.replaceOwned(u8, self.allocator, with_output, "__ARGI_TRACER_SETUP__", tracer);
        defer self.allocator.free(with_tracer);
        const report_setup = if (!needs_reporting) "" else if (takes_system) "assume writer ::= $&terminal&.stderr" else "ffi_storage ::= ForeignFunctionInterface()\n    assume ffi ::= $&ffi_storage\n    terminal_storage ::= Terminal()\n    assume writer ::= $&terminal_storage.stderr";
        const with_report = try std.mem.replaceOwned(u8, self.allocator, with_tracer, "__ARGI_REPORT_SETUP__", report_setup);
        defer self.allocator.free(with_report);
        self.entry_source = try std.mem.replaceOwned(u8, self.allocator, with_report, "__ARGI_CALL__", call);
        self.entry_path = try std.fs.path.join(self.allocator, &.{ dir, "<program-entry>" });
        self.entry_file = try self.diagnostics.appendSource(.{ .path = self.entry_path.?, .code = self.entry_source.? });
        var tokens = tokenizer.Tokenizer.init(self.allocator, self.diagnostics, self.entry_source.?, self.entry_file.?);
        defer tokens.deinit();
        _ = try tokens.tokenize();
        const file = st.FileSyntaxTree.initOwnedTokens(self.entry_file.?, tokens.takeTokens());
        var syntax_ctx = syntaxer.Syntaxer.initFile(self.allocator, file, self.entry_source.?, self.diagnostics);
        const tree = try syntax_ctx.parse();
        try self.syntax_files.append(tree);
        self.syntax_node_count += tree.nodes.len;
        for (tree.roots) |node| try self.syntax_root_list.append(tree.ref(node));
    }

    fn validateFunctionSignatures(self: *FrontendPipeline) !void {
        for (self.syntax_files.items) |*file| {
            const source = self.source_db.get(file.file_id).source;
            for (file.roots) |root| {
                const function = file.functionDeclaration(root) orelse continue;
                try self.validateFunctionSignatureFields(file, source, function.input, "input");
                try self.validateFunctionSignatureFields(file, source, function.output, "output");
            }
        }
    }

    fn validateFunctionSignatureFields(
        self: *FrontendPipeline,
        file: *const st.FileSyntaxTree,
        source: []const u8,
        node: st.NodeIndex,
        direction: []const u8,
    ) !void {
        const literal = file.structTypeLiteral(node) orelse return;
        for (literal.fields) |field_node| {
            const field = file.structTypeField(field_node) orelse continue;
            if (field.type_node != null or field.inferred_result) continue;
            const name = file.tokenTextFromSource(source, field.name_token);
            try self.diagnostics.add(
                file.tokenLocation(field.name_token),
                .semantic,
                "function {s} field '.{s}' requires an explicit type",
                .{ direction, name },
            );
        }
    }

    fn analyzeGlobalSafety(self: *FrontendPipeline) !void {
        if (self.safety_ctx) |*ctx| ctx.deinit();
        self.safety_ctx = null;
        const graph = &self.global_graph.?;
        self.safety_ctx = global_safety_checker.SafetyChecker.init(self.allocator, self.diagnostics, graph);
        if (self.options.collect_stats) self.safety_ctx.?.enableStats(self.io);
        const safety_start = std.Io.Timestamp.now(self.io, .boot).nanoseconds;
        try self.safety_ctx.?.analyze();
        self.safety_ns = @intCast(std.Io.Timestamp.now(self.io, .boot).nanoseconds - safety_start);
        self.global_safety_stats = self.safety_ctx.?.stats;
    }

    fn buildModuleGraphs(self: *FrontendPipeline) !void {
        const module_start = std.Io.Timestamp.now(self.io, .boot).nanoseconds;
        self.clearModuleGraphs();
        errdefer self.clearModuleGraphs();
        self.module_lowered_functions = 0;
        self.module_cache_hits = 0;
        self.module_cache_misses = 0;

        const ModuleInputs = struct {
            dir: []const u8,
            files: std.ArrayList(module_sg.FileInput) = .empty,
            source_fingerprint: cache.Fingerprint = @splat(0),
        };
        var groups: std.ArrayList(ModuleInputs) = .empty;
        defer {
            for (groups.items) |*group| group.files.deinit(self.allocator);
            groups.deinit(self.allocator);
        }
        for (self.syntax_files.items) |*file| {
            const source = self.source_db.get(file.file_id);
            const dir = std.fs.path.dirname(source.path) orelse ".";
            var group_index: ?usize = null;
            for (groups.items, 0..) |group, index| if (std.mem.eql(u8, group.dir, dir)) {
                group_index = index;
                break;
            };
            if (group_index == null) {
                try groups.append(self.allocator, .{ .dir = dir });
                group_index = groups.items.len - 1;
            }
            try groups.items[group_index.?].files.append(self.allocator, .{
                .path = source.path,
                .tree = file,
                .diagnostics = self.diagnostics,
                .source = source.source,
                .is_bundled_core = source.origin == .bundled_core,
                .is_entry = file.file_id == self.entry_file,
            });
        }
        var core_hash = cache.ContentHash.init(.{});
        if (self.options.module_cache != null) {
            for (groups.items) |*group| {
                var hash = cache.ContentHash.init(.{});
                cache.hashBytes(&hash, group.dir);
                for (group.files.items) |file| hashFile(&hash, file);
                group.source_fingerprint = cache.finishHash(&hash);
                if (group.files.items[0].is_bundled_core) {
                    cache.hashBytes(&core_hash, group.dir);
                    core_hash.update(&group.source_fingerprint);
                }
            }
        }
        const core_fingerprint = cache.finishHash(&core_hash);
        try self.module_graphs.ensureTotalCapacity(self.allocator, groups.items.len);
        try self.module_entries.ensureTotalCapacity(self.allocator, groups.items.len);
        try self.module_arenas.ensureTotalCapacity(self.allocator, groups.items.len);
        const jobs = try self.allocator.alloc(ModuleJob, groups.items.len);
        defer self.allocator.free(jobs);
        var initialized: usize = 0;
        var active_jobs: usize = 0;
        defer for (jobs[0..initialized]) |*job| job.diagnostics.deinit();
        // Cache access and leases stay on the coordinator. All task slots and
        // arenas have stable addresses before any worker can start.
        for (groups.items, 0..) |group, index| {
            const arena: *std.heap.ArenaAllocator = if (self.options.module_cache) |session| blk: {
                const fingerprint = self.moduleFingerprint(group.source_fingerprint, core_fingerprint);
                const hit = session.acquire(group.dir, fingerprint);
                const entry = hit orelse try session.create(fingerprint);
                self.module_entries.appendAssumeCapacity(entry);
                self.module_graphs.appendAssumeCapacity(entry.graph);
                if (hit != null) self.module_cache_hits += 1 else self.module_cache_misses += 1;
                break :blk &entry.arena;
            } else blk: {
                self.module_arenas.appendAssumeCapacity(std.heap.ArenaAllocator.init(self.allocator));
                self.module_graphs.appendAssumeCapacity(.{});
                break :blk &self.module_arenas.items[index];
            };
            const job = &jobs[index];
            job.* = .{
                .arena = arena,
                .original_backing = arena.child_allocator,
                .needs_run = !self.module_graphs.items[index].semantic.local_semantics_complete,
                .allocator = arena.allocator(),
                .graph = &self.module_graphs.items[index],
                .dir = group.dir,
                .files = group.files.items,
                .target = self.options.target,
                .diagnostics = undefined,
            };
            job.diagnostics = diag.Diagnostics.initBorrowed(&job.allocator, self.diagnostics);
            initialized += 1;
            active_jobs += @intFromBool(job.needs_run);
            for (job.files) |*file| file.diagnostics = &job.diagnostics;
        }
        const workers = @min(@max(1, self.options.module_jobs), active_jobs);
        if (workers <= 1) {
            for (jobs) |*job| job.run();
        } else {
            // The caller's allocator may be an arena. Only backing growth is
            // serialized; each module's allocation state belongs to one task.
            var backing: @import("locked_allocator.zig").LockedAllocator = .{ .child_allocator = if (self.options.module_cache) |session| session.allocator else self.allocator, .io = self.io };
            for (jobs) |*job| {
                if (job.needs_run) job.arena.child_allocator = backing.allocator();
            }
            defer {
                for (jobs) |*job| {
                    if (job.needs_run) job.arena.child_allocator = job.original_backing;
                }
            }
            var queue: ModuleQueue = .{ .jobs = jobs };
            var group: std.Io.Group = .init;
            defer group.cancel(self.io);
            for (0..workers) |_| group.async(self.io, ModuleQueue.work, .{&queue});
            try group.await(self.io);
        }
        // Publish in source module order, never worker completion order. Copy
        // diagnostic text into the invocation's storage before task cleanup.
        var failure: ?anyerror = null;
        for (jobs, 0..) |*job, index| {
            for (job.diagnostics.list.items) |message|
                try self.diagnostics.add(message.loc, message.kind, "{s}", .{message.msg});
            if (failure == null) failure = job.failure;
            self.module_lowered_functions += job.stats.lowered_functions;
            if (self.options.module_cache != null)
                self.module_entries.items[index].graph = self.module_graphs.items[index];
        }
        if (failure) |err| return err;

        // Cached graphs are immutable module-local artifacts.
        if (!self.diagnostics.hasErrors()) if (self.options.module_cache) |session| {
            for (self.module_entries.items) |entry| try session.publish(entry);
        };

        self.module_semantizing_ns = @intCast(std.Io.Timestamp.now(self.io, .boot).nanoseconds - module_start);
    }

    fn buildGlobalGraph(self: *FrontendPipeline) !void {
        try self.buildModuleGraphs();
        const global_start = std.Io.Timestamp.now(self.io, .boot).nanoseconds;
        const has_conditions = for (self.module_graphs.items) |module| {
            if (module.conditions.items.len != 0) break true;
        } else false;
        const result = if (has_conditions) try self.buildStagedGlobalGraph() else try global_semantizer.semantizeWithOptions(self.allocator, self.module_graphs.items, .{
            .target = self.options.target,
            .selected_test_name = self.options.semantizing.selected_test_name,
            .exhaustive_function_bodies = self.options.semantizing.exhaustive_function_bodies,
            .root_selection = self.options.semantizing.root_selection,
            .diagnostics = self.diagnostics,
            .profile_io = if (self.options.collect_stats) self.io else null,
        });
        self.global_graph = result.graph;
        self.global_stats = result.stats;
        try global_once_verify.verify(
            self.allocator,
            &self.global_graph.?,
            self.diagnostics,
            self.options.semantizing.selected_test_name,
        );
        self.global_semantic_ns = @intCast(std.Io.Timestamp.now(self.io, .boot).nanoseconds - global_start);
    }

    fn buildStagedGlobalGraph(self: *FrontendPipeline) !global_semantizer.Result {
        var session: global_semantizer.Session = undefined;
        try self.prepareStagedSession(&session);
        defer session.deinit();
        return session.finish();
    }

    fn prepareStagedSession(self: *FrontendPipeline, session: *global_semantizer.Session) !void {
        const arena = try self.allocator.create(std.heap.ArenaAllocator);
        arena.* = .init(self.allocator);
        self.staged_arena = arena;
        const a = arena.allocator();
        var modules: std.ArrayList(module_sg.ModuleSemanticGraph) = .empty;
        try modules.appendSlice(a, self.module_graphs.items);
        try session.init(self.allocator, modules.items, .{
            .target = self.options.target,
            .selected_test_name = self.options.semantizing.selected_test_name,
            .exhaustive_function_bodies = self.options.semantizing.exhaustive_function_bodies,
            .root_selection = self.options.semantizing.root_selection,
            .diagnostics = self.diagnostics,
        });
        errdefer session.deinit();
        var loader = SelectionLoader{ .pipeline = self, .allocator = a, .modules = &modules };
        try @import("../4_semantics/global/module_selection.zig").resolve(a, session, 0, &loader);
        try module_test_declaration_verify.validate(self.syntax_files.items, self.source_db, self.diagnostics, self.options.semantizing.include_tests, self.options.semantizing.selected_test_name);
        if (self.deferred_entry) {
            const before = self.syntax_files.items.len;
            try self.appendProgramEntry();
            if (self.syntax_files.items.len != before) {
                const file = &self.syntax_files.items[before];
                const input = module_sg.FileInput{ .path = self.entry_path.?, .tree = file, .source = self.entry_source.?, .is_entry = true, .diagnostics = self.diagnostics };
                const result = try module_semantizer.buildForTarget(a, self.options.entry_module_dir.?, &.{input}, self.options.target);
                const owner = for (modules.items, 0..) |module, index| {
                    if (std.mem.eql(u8, module.module_dir, self.options.entry_module_dir.?)) break @as(global_sg.GlobalModuleId, @enumFromInt(index));
                } else return error.InvalidEntryModule;
                try modules.append(a, result.graph);
                try session.appendModuleFragment(modules.items, owner);
            }
        }
        try self.validateFunctionSignatures();
        try @import("../4_semantics/module/assume_verify.zig").validate(self.allocator, self.syntax_files.items, self.source_db, self.diagnostics);
        if (self.diagnostics.hasErrors()) return error.Reported;
        try session.advance();
    }

    const SelectionLoader = struct {
        pipeline: *FrontendPipeline,
        allocator: std.mem.Allocator,
        modules: *std.ArrayList(module_sg.ModuleSemanticGraph),

        pub fn materialize(self: *SelectionLoader, session: *global_semantizer.Session, module_index: usize, condition: module_sg.ModuleCondition, decision: bool) !void {
            const pipeline = self.pipeline;
            const a = self.allocator;
            const module = session.modules[module_index];
            const path = try std.fs.path.join(a, &.{ module.module_dir, module.text(module.file_offsets.items[condition.source.file_index].path) });
            const file_id = pipeline.source_db.findPath(path) orelse return error.InvalidModuleConditionSource;
            const selection = &pipeline.source_selections.items[@intFromEnum(file_id)];
            const branch = for (selection.plan.branches.items, 0..) |candidate, branch_index| {
                if (candidate.extent.start == condition.source.offset) break @as(@import("../1_base/conditional_source.zig").BranchId, @enumFromInt(branch_index));
            } else return error.InvalidModuleConditionSource;
            try selection.resolve(branch, decision);
            const rendered = try selection.fragment(a, branch, true);
            const imports = try selection.fragment(a, branch, false);
            try pipeline.discoverSelectedImports(a, session, self.modules, path, imports.source);
            const fragment = try pipeline.buildSelectedFragment(a, path, file_id, rendered.source, module.is_bundled_core);
            try self.modules.append(a, fragment);
            try session.appendModuleFragment(self.modules.items, @enumFromInt(module_index));
        }
    };

    fn discoverSelectedImports(self: *FrontendPipeline, a: std.mem.Allocator, session: *global_semantizer.Session, modules: *std.ArrayList(module_sg.ModuleSemanticGraph), path: []const u8, source: []const u8) !void {
        if (sf.firstImportDirectiveOffset(source) == null) return;
        const dirs = try a.alloc([]const u8, modules.items.len);
        for (dirs, modules.items) |*dir, module| dir.* = module.module_dir;
        const loaded = try sf.collectImportedModules(&a, self.io, .{ .path = path, .code = source }, dirs, .{ .target = self.options.target, .source_overrides = self.diagnostics.source_files });
        try self.syntax_files.ensureUnusedCapacity(loaded.items.len);
        var start: usize = 0;
        while (start < loaded.items.len) {
            const dir = std.fs.path.dirname(loaded.items[start].path) orelse ".";
            var end = start + 1;
            while (end < loaded.items.len and std.mem.eql(u8, std.fs.path.dirname(loaded.items[end].path) orelse ".", dir)) : (end += 1) {}
            var inputs: std.ArrayList(module_sg.FileInput) = .empty;
            try inputs.ensureTotalCapacity(a, end - start);
            for (loaded.items[start..end]) |file| {
                const file_id = try self.diagnostics.appendSource(file);
                var offset: usize = 0;
                var selection = @import("../1_base/target_selection.zig").Prepared.init(self.allocator, file.code, self.options.target, &offset, .computed) catch |err| {
                    if (err == error.OutOfMemory) return err;
                    try self.diagnostics.add(.{ .file = file_id, .offset = @intCast(offset) }, .syntax, "invalid target selection: {s}", .{@import("../1_base/target_selection.zig").errorMessage(err)});
                    return error.Reported;
                };
                errdefer selection.deinit(self.allocator);
                const rendered = try selection.syntax(a);
                var tokens = tokenizer.Tokenizer.init(self.allocator, self.diagnostics, rendered.source, file_id);
                defer tokens.deinit();
                _ = try tokens.tokenize();
                var parser = syntaxer.Syntaxer.initFile(self.allocator, st.FileSyntaxTree.initOwnedTokens(file_id, tokens.takeTokens()), rendered.source, self.diagnostics);
                defer parser.deinit();
                var tree = try parser.parse();
                errdefer tree.deinit(self.allocator);
                try self.validateSelectedSyntax(&tree);
                if (@intFromEnum(file_id) != self.source_selections.items.len) return error.InvalidModuleConditionSource;
                try self.source_selections.append(self.allocator, selection);
                self.syntax_files.appendAssumeCapacity(tree);
                inputs.appendAssumeCapacity(.{ .path = file.path, .tree = &self.syntax_files.items[self.syntax_files.items.len - 1], .source = file.code, .diagnostics = self.diagnostics });
            }
            const built = try module_semantizer.buildForTarget(a, dir, inputs.items, self.options.target);
            try modules.append(a, built.graph);
            try session.appendModules(modules.items);
            start = end;
        }
    }

    fn buildSelectedFragment(self: *FrontendPipeline, a: std.mem.Allocator, path: []const u8, file_id: source_db.FileId, source: []const u8, bundled: bool) !module_sg.ModuleSemanticGraph {
        var tokens = tokenizer.Tokenizer.init(self.allocator, self.diagnostics, source, file_id);
        defer tokens.deinit();
        _ = try tokens.tokenize();
        var parser = syntaxer.Syntaxer.initFile(self.allocator, st.FileSyntaxTree.initOwnedTokens(file_id, tokens.takeTokens()), source, self.diagnostics);
        defer parser.deinit();
        var tree = try parser.parse();
        errdefer tree.deinit(self.allocator);
        try self.validateSelectedSyntax(&tree);
        const input = module_sg.FileInput{ .path = path, .tree = &tree, .source = source, .is_bundled_core = bundled, .diagnostics = self.diagnostics };
        const result = try module_semantizer.buildForTarget(a, std.fs.path.dirname(path) orelse ".", &.{input}, self.options.target);
        try self.syntax_files.append(tree);
        return result.graph;
    }

    fn validateSelectedSyntax(self: *FrontendPipeline, tree: *const st.FileSyntaxTree) !void {
        if (self.diagnostics.hasErrors()) return error.Reported;
        try module_test_declaration_verify.validate(&.{tree.*}, self.source_db, self.diagnostics, self.options.semantizing.include_tests, self.options.semantizing.selected_test_name);
        const source = self.source_db.get(tree.file_id).source;
        for (tree.roots) |root| {
            const function = tree.functionDeclaration(root) orelse continue;
            try self.validateFunctionSignatureFields(tree, source, function.input, "input");
            try self.validateFunctionSignatureFields(tree, source, function.output, "output");
        }
        try @import("../4_semantics/module/assume_verify.zig").validate(self.allocator, &.{tree.*}, self.source_db, self.diagnostics);
        if (self.diagnostics.hasErrors()) return error.Reported;
    }

    const ModuleJob = struct {
        arena: *std.heap.ArenaAllocator,
        original_backing: std.mem.Allocator,
        needs_run: bool,
        allocator: std.mem.Allocator,
        graph: *module_sg.ModuleSemanticGraph,
        dir: []const u8,
        files: []module_sg.FileInput,
        target: @import("../1_base/target.zig").Config,
        diagnostics: diag.Diagnostics,
        stats: module_semantizer.BuildStats = .{},
        failure: ?anyerror = null,

        fn run(job: *ModuleJob) void {
            if (job.graph.semantic.local_semantics_complete) return;
            job.graph.* = module_sg.buildForTarget(job.allocator, job.dir, job.files, job.target) catch |err| {
                job.failure = err;
                return;
            };
            job.stats = module_semantizer.finish(job.allocator, job.graph, job.files, &job.diagnostics) catch |err| {
                job.failure = err;
                return;
            };
        }
    };

    const ModuleQueue = struct {
        jobs: []ModuleJob,
        next: std.atomic.Value(usize) = .init(0),

        fn work(queue: *ModuleQueue) void {
            while (true) {
                const index = queue.next.fetchAdd(1, .monotonic);
                if (index >= queue.jobs.len) return;
                queue.jobs[index].run();
            }
        }
    };

    fn hashFile(hash: *cache.ContentHash, file: module_sg.FileInput) void {
        cache.hashBytes(hash, file.path);
        cache.hashBytes(hash, file.source);
        hash.update(&.{ @intFromBool(file.is_bundled_core), @intFromBool(file.is_entry) });
    }

    fn moduleFingerprint(self: *const FrontendPipeline, source: cache.Fingerprint, core: cache.Fingerprint) cache.Fingerprint {
        var hash = cache.ContentHash.init(.{});
        cache.hashConfiguration(&hash);
        cache.hashBytes(&hash, @tagName(self.options.target.arch));
        cache.hashBytes(&hash, @tagName(self.options.target.os));
        cache.hashBytes(&hash, @tagName(self.options.target.abi));
        hash.update(&source);
        hash.update(&core);
        const options = self.options.semantizing;
        hash.update(&.{
            @intFromBool(options.include_tests),              @intFromBool(options.exhaustive_function_bodies),
            @intFromBool(options.selected_test_name != null), @intFromBool(options.implicit_testing_module_dir != null),
        });
        cache.hashBytes(&hash, options.selected_test_name orelse "");
        cache.hashBytes(&hash, options.implicit_testing_module_dir orelse "");
        return cache.finishHash(&hash);
    }

    fn clearModuleGraphs(self: *FrontendPipeline) void {
        if (self.prepared_session) |session| {
            session.deinit();
            self.allocator.destroy(session);
            self.prepared_session = null;
        }
        if (self.safety_ctx) |*ctx| ctx.deinit();
        self.safety_ctx = null;
        if (self.global_graph) |*graph| graph.deinit(self.allocator);
        self.global_graph = null;
        if (self.options.module_cache != null) {
            for (self.module_entries.items) |entry| entry.release();
            self.module_entries.clearRetainingCapacity();
        } else {
            for (self.module_graphs.items, self.module_arenas.items) |*graph, *arena| {
                graph.deinit(arena.allocator());
                arena.deinit();
            }
            self.module_arenas.clearRetainingCapacity();
        }
        self.module_graphs.clearRetainingCapacity();
        if (self.staged_arena) |arena| {
            arena.deinit();
            self.allocator.destroy(arena);
            self.staged_arena = null;
        }
    }

    pub fn moduleSemanticStorageBytes(self: *const FrontendPipeline) usize {
        var bytes: usize = 0;
        for (self.module_graphs.items) |*graph| bytes += graph.storageBytes();
        return bytes;
    }

    pub fn globalSemanticStorageBytes(self: *const FrontendPipeline) usize {
        return if (self.global_graph) |*graph| graph.storageBytes() else 0;
    }
};
