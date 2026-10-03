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
const module_linker = @import("../4_semantics/global/module_linker.zig");
const global_once_verify = @import("../4_semantics/global/once_verify.zig");
const module_test_declaration_verify = @import("../4_semantics/module/test_declaration_verify.zig");
const global_safety_checker = @import("../4_semantics/safety/checker.zig");

pub const FrontendPipeline = struct {
    pub const SemantizingOptions = struct {
        include_tests: bool = false,
        selected_test_name: ?[]const u8 = null,
        implicit_testing_module_dir: ?[]const u8 = null,
        exhaustive_function_bodies: bool = false,
    };

    pub const Options = struct {
        target: @import("../1_base/target.zig").Config = .{},
        semantizing: SemantizingOptions = .{},
        collect_stats: bool = false,
        entry_module_dir: ?[]const u8 = null,
        module_cache: ?*cache.ModuleCache = null,
    };

    allocator: std.mem.Allocator,
    io: std.Io,
    diagnostics: *diag.Diagnostics,
    options: Options,
    source_db: *const source_db.SourceDb,
    syntax_files: std.array_list.Managed(st.FileSyntaxTree),
    syntax_root_list: std.array_list.Managed(st.SyntaxRef),
    module_graphs: std.ArrayList(module_sg.ModuleSemanticGraph) = .empty,
    module_entries: std.ArrayList(*cache.ModuleCache.Entry) = .empty,
    module_cache_hits: usize = 0,
    module_cache_misses: usize = 0,
    linked_module_count: usize = 0,
    linked_module_ns: u64 = 0,
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
        for (self.syntax_files.items) |*file| file.deinit(self.allocator);
        self.syntax_files.deinit();
        self.syntax_root_list.deinit();
        if (self.entry_source) |value| self.allocator.free(value);
        if (self.entry_path) |value| self.allocator.free(value);
    }

    pub fn tokenizeFiles(self: *FrontendPipeline, files: []const sf.SourceFile) !void {
        self.clearModuleGraphs();
        for (self.syntax_files.items) |*file| file.deinit(self.allocator);
        self.syntax_files.clearRetainingCapacity();

        for (files, 0..) |source_file, index| {
            var error_offset: usize = 0;
            const selected = @import("../1_base/target_selection.zig").select(self.allocator, source_file.code, self.options.target, &error_offset) catch |err| {
                try self.diagnostics.add(.{ .file = self.source_db.fileId(index), .offset = @intCast(error_offset) }, .syntax, "invalid target selection: {s}", .{@import("../1_base/target_selection.zig").errorMessage(err)});
                return err;
            };
            defer self.allocator.free(selected);
            var tokenizer_ctx = tokenizer.Tokenizer.init(
                self.allocator,
                self.diagnostics,
                selected,
                self.source_db.fileId(index),
            );
            defer tokenizer_ctx.deinit();
            _ = try tokenizer_ctx.tokenize();
            var file = st.FileSyntaxTree.initOwnedTokens(self.source_db.fileId(index), tokenizer_ctx.takeTokens());
            errdefer file.deinit(self.allocator);
            try self.syntax_files.append(file);
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

    /// Produce and safety-check the final indexed semantic graph. This is the
    /// sole semantic output API of the frontend.
    pub fn semantizeGlobalFiles(self: *FrontendPipeline, files: []const sf.SourceFile) !*const global_sg.GlobalSemanticGraph {
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
        try self.appendProgramEntry();
        try self.validateFunctionSignatures();
        try @import("../4_semantics/module/assume_verify.zig").validate(self.allocator, self.syntax_files.items, self.source_db, self.diagnostics);
        if (self.diagnostics.hasErrors()) return error.Reported;
        try self.buildGlobalGraph();
        try self.analyzeGlobalSafety();
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
        for (self.syntax_files.items) |*file| {
            const source = self.source_db.get(file.file_id);
            if (!std.mem.eql(u8, std.fs.path.dirname(source.path) orelse ".", dir)) continue;
            for (file.roots) |root| {
                const function = if (file.testDeclaration(root)) |test_decl| test_decl.function else file.functionDeclaration(root) orelse continue;
                const name = file.tokenText(self.source_db, function.name_token);
                if (std.mem.eql(u8, name, target)) {
                    found = true;
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
        const with_output = try std.mem.replaceOwned(u8, self.allocator, template, "__ARGI_OUTPUT__", output);
        defer self.allocator.free(with_output);
        const with_result = try std.mem.replaceOwned(u8, self.allocator, with_output, "__ARGI_RESULT__", result);
        defer self.allocator.free(with_result);
        self.entry_source = try std.mem.replaceOwned(u8, self.allocator, with_result, "__ARGI_TARGET__", target);
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

    fn buildGlobalGraph(self: *FrontendPipeline) !void {
        const module_start = std.Io.Timestamp.now(self.io, .boot).nanoseconds;
        self.clearModuleGraphs();
        errdefer self.clearModuleGraphs();
        self.module_lowered_functions = 0;
        self.module_cache_hits = 0;
        self.module_cache_misses = 0;
        self.linked_module_count = 0;
        self.linked_module_ns = 0;

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
        // Discover every module before semantic finishing. This exposes the
        // bundled-core declaration surface early enough to derive the language
        // prelude without making ordinary ModuleSema depend on arbitrary user
        // modules.
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
        if (self.options.module_cache != null)
            try self.module_entries.ensureTotalCapacity(self.allocator, groups.items.len);
        for (groups.items) |group| {
            if (self.options.module_cache) |session| {
                const fingerprint = self.moduleFingerprint(group.source_fingerprint, core_fingerprint);
                if (session.acquire(group.dir, fingerprint)) |entry| {
                    self.module_entries.appendAssumeCapacity(entry);
                    self.module_graphs.appendAssumeCapacity(entry.graph);
                    self.module_cache_hits += 1;
                } else {
                    const entry = try session.create(fingerprint);
                    errdefer entry.release();
                    entry.graph = try module_sg.buildForTarget(entry.allocator(), group.dir, group.files.items, self.options.target);
                    self.module_entries.appendAssumeCapacity(entry);
                    self.module_graphs.appendAssumeCapacity(entry.graph);
                    self.module_cache_misses += 1;
                }
            } else {
                const graph = try module_sg.buildForTarget(self.allocator, group.dir, group.files.items, self.options.target);
                self.module_graphs.appendAssumeCapacity(graph);
            }
        }

        // Bundled core is compiler semantic configuration: its abstracts are
        // available as unqualified prelude names. Include this configuration in
        // the durable ModuleSG build/cache key rather than discovering it by
        // relowering modules after the fact.
        var prelude_abstracts: std.ArrayList(module_semantizer.QualifiedAbstract) = .empty;
        defer {
            for (prelude_abstracts.items) |candidate| self.allocator.free(candidate.name);
            prelude_abstracts.deinit(self.allocator);
        }
        for (self.module_graphs.items) |*candidate_module| {
            if (!candidate_module.is_bundled_core) continue;
            for (candidate_module.declarations.items) |declaration| {
                if (declaration.kind != .abstract_type) continue;
                // The source graph is not semantically finished yet; finishing
                // can grow/reallocate its string pool. Keep the prelude catalog
                // independent from those mutable buffers.
                const name = try self.allocator.dupe(u8, candidate_module.text(declaration.name));
                errdefer self.allocator.free(name);
                try prelude_abstracts.append(self.allocator, .{
                    .qualifier = null,
                    .name = name,
                });
            }
        }

        // Finish each durable module exactly once with the prelude already
        // known. Cross-user-module declaration kinds remain unresolved here.
        for (self.module_graphs.items, 0..) |*module, module_index| {
            if (module.semantic.local_semantics_complete) continue;
            const module_allocator = if (self.options.module_cache != null)
                self.module_entries.items[module_index].allocator()
            else
                self.allocator;
            const stats = try module_semantizer.finishLinked(
                module_allocator,
                module,
                groups.items[module_index].files.items,
                prelude_abstracts.items,
                self.diagnostics,
            );
            self.module_lowered_functions += stats.lowered_functions;
            if (self.options.module_cache != null)
                self.module_entries.items[module_index].graph = module.*;
        }

        // Cached graphs are immutable module-local artifacts. Qualified imported
        // abstracts still produce a fresh derivative below for each compilation.
        if (!self.diagnostics.hasErrors()) if (self.options.module_cache) |session| {
            for (self.module_entries.items) |entry| try session.publish(entry);
        };

        var module_dirs: std.ArrayList([]const u8) = .empty;
        defer module_dirs.deinit(self.allocator);
        for (self.module_graphs.items) |*module| try module_dirs.append(self.allocator, module.module_dir);
        var linked_graphs: std.ArrayList(module_sg.ModuleSemanticGraph) = .empty;
        defer {
            for (linked_graphs.items) |*graph| graph.deinit(self.allocator);
            linked_graphs.deinit(self.allocator);
        }
        var selected_graphs: std.ArrayList(module_sg.ModuleSemanticGraph) = .empty;
        defer selected_graphs.deinit(self.allocator);

        for (self.module_graphs.items, 0..) |*module, module_index| {
            // Only imported user/module-qualified abstracts can require a
            // derivative now; unqualified prelude abstracts were already part
            // of the one durable finishing pass above.
            var imported_abstracts: std.ArrayList(module_semantizer.QualifiedAbstract) = .empty;
            defer imported_abstracts.deinit(self.allocator);
            for (module.semantic.module_aliases.items) |alias| {
                const target_index = try module_linker.resolveImportPathFromDirs(
                    self.allocator,
                    module_dirs.items,
                    module_index,
                    module.text(alias.path),
                );
                const qualifier = module.text(module.declaration(alias.declaration).name);
                const target = &self.module_graphs.items[target_index];
                for (target.declarations.items) |declaration| {
                    if (declaration.kind != .abstract_type) continue;
                    try imported_abstracts.append(self.allocator, .{
                        .qualifier = qualifier,
                        .name = target.text(declaration.name),
                    });
                }
            }

            const needs_linked_graph = module_semantizer.needsLinkedLowering(
                module,
                groups.items[module_index].files.items,
                imported_abstracts.items,
            );
            if (needs_linked_graph) {
                var linked_abstracts: std.ArrayList(module_semantizer.QualifiedAbstract) = .empty;
                defer linked_abstracts.deinit(self.allocator);
                try linked_abstracts.appendSlice(self.allocator, prelude_abstracts.items);
                try linked_abstracts.appendSlice(self.allocator, imported_abstracts.items);

                const linked_start = std.Io.Timestamp.now(self.io, .boot).nanoseconds;
                const linked = try module_semantizer.buildLinkedForTarget(
                    self.allocator,
                    groups.items[module_index].dir,
                    groups.items[module_index].files.items,
                    linked_abstracts.items,
                    self.options.target,
                );
                self.linked_module_ns += @intCast(std.Io.Timestamp.now(self.io, .boot).nanoseconds - linked_start);
                self.linked_module_count += 1;
                try linked_graphs.append(self.allocator, linked.graph);
                try selected_graphs.append(self.allocator, linked_graphs.items[linked_graphs.items.len - 1]);
                self.module_lowered_functions += linked.stats.lowered_functions;
            } else {
                try selected_graphs.append(self.allocator, module.*);
            }
        }
        self.module_semantizing_ns = @intCast(std.Io.Timestamp.now(self.io, .boot).nanoseconds - module_start);

        const global_start = std.Io.Timestamp.now(self.io, .boot).nanoseconds;
        const result = try global_semantizer.semantizeWithOptions(self.allocator, selected_graphs.items, .{
            .target = self.options.target,
            .selected_test_name = self.options.semantizing.selected_test_name,
            .exhaustive_function_bodies = self.options.semantizing.exhaustive_function_bodies,
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
        if (self.safety_ctx) |*ctx| ctx.deinit();
        self.safety_ctx = null;
        if (self.global_graph) |*graph| graph.deinit(self.allocator);
        self.global_graph = null;
        if (self.options.module_cache != null) {
            for (self.module_entries.items) |entry| entry.release();
            self.module_entries.clearRetainingCapacity();
        } else {
            for (self.module_graphs.items) |*graph| graph.deinit(self.allocator);
        }
        self.module_graphs.clearRetainingCapacity();
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
