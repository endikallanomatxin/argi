const std = @import("std");
const module_sg = @import("../4_semantics/module/graph.zig");
const sema = @import("../4_semantics/global/semantizer.zig");
const selection_mod = @import("../1_base/target_selection.zig");
const FileId = @import("../1_base/source_db.zig").FileId;
const diagnostics_mod = @import("../1_base/diagnostic.zig");

/// Owns immutable submitted source and syntax-free module graphs. Initialize in
/// final storage. Diagnostics borrow source buffers, including rejected input,
/// so this owner must outlive their use. Accepted module-prefix snapshots can
/// borrow these graphs without replaying source or retaining syntax trees.
pub const Sources = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    modules: std.ArrayList(*module_sg.ModuleSemanticGraph) = .empty,
    sequence: u64 = 0,
    // Published slices share initialized prefixes. Only the unpublished tail of
    // the current buffer may be filled; branching starts a separate buffer.
    snapshot_tail: []module_sg.ModuleSemanticGraph = &.{},
    snapshot_len: usize = 0,
    selections: std.AutoHashMapUnmanaged(FileId, selection_mod.Prepared) = .empty,

    pub fn init(allocator: std.mem.Allocator) Sources {
        return .{ .allocator = allocator, .arena = .init(allocator) };
    }
    pub fn deinit(self: *Sources) void {
        for (self.modules.items) |module| {
            module.deinit(self.allocator);
            self.allocator.destroy(module);
        }
        self.modules.deinit(self.allocator);
        var selections = self.selections.valueIterator();
        while (selections.next()) |selection| selection.deinit(self.allocator);
        self.selections.deinit(self.allocator);
        self.arena.deinit();
        self.* = undefined;
    }

    pub const Command = struct {
        module: *const module_sg.ModuleSemanticGraph,
        function: @import("../4_semantics/module/entities.zig").ModuleFunctionId,
    };

    /// Parse statements in a fresh ordinary function scope. The semantic
    /// coordinator subsequently designates it as a continuation before cleanup.
    /// Each source unit has its own identity; no preceding text is replayed.
    pub fn loadCommand(self: *Sources, diagnostics: *diagnostics_mod.Diagnostics, statements: []const u8) !Command {
        return self.loadCommandOrigin(diagnostics, statements, null);
    }

    pub const SourceOrigin = struct { text: []const u8, offset: usize };

    fn loadCommandOrigin(self: *Sources, diagnostics: *diagnostics_mod.Diagnostics, statements: []const u8, origin: ?SourceOrigin) !Command {
        const a = self.arena.allocator();
        const name = try std.fmt.allocPrint(a, "_session_command_{d}", .{self.sequence});
        const header = try std.fmt.allocPrint(a, "{s} := () -> () {{\n", .{name});
        const source = try std.fmt.allocPrint(a, "{s}{s}\n}}\n", .{ header, statements });
        const input = origin orelse SourceOrigin{ .text = statements, .offset = 0 };
        const module = try self.loadModuleOrigin(diagnostics, source, .{ .text = input.text, .offset = try std.math.add(usize, header.len, input.offset) });
        for (module.declarations.items) |declaration| {
            if (std.mem.eql(u8, module.text(declaration.name), name)) {
                return .{ .module = module, .function = declaration.function_id orelse return error.InvalidCommand };
            }
        }
        return error.InvalidCommand;
    }

    pub const PreparedCommand = struct {
        candidate: @import("compilation_session.zig").CompilationSession.Candidate,
        function: @import("../4_semantics/global/graph.zig").GlobalFunctionId,

        pub fn deinit(self: *PreparedCommand) void {
            self.candidate.deinit();
            self.* = undefined;
        }
    };

    /// Join source loading to retained semantic preparation. Rejected sources
    /// remain available for diagnostics but never enter the accepted prefix.
    pub fn prepareCommand(self: *Sources, compiler: *const @import("compilation_session.zig").CompilationSession, diagnostics: *diagnostics_mod.Diagnostics, statements: []const u8) !PreparedCommand {
        return self.prepareCommandOrigin(compiler, diagnostics, statements, null);
    }

    pub fn prepareCommandOrigin(self: *Sources, compiler: *const @import("compilation_session.zig").CompilationSession, diagnostics: *diagnostics_mod.Diagnostics, statements: []const u8, origin: ?SourceOrigin) !PreparedCommand {
        const command = try self.loadCommandOrigin(diagnostics, statements, origin);
        const modules = try self.appendSnapshot(compiler.semantic.modules, command.module);
        // Relocation appends module functions before creating any specialization.
        const base = compiler.semantic.relocation.graph.functions.items.len;
        const raw = std.math.add(usize, base, @intFromEnum(command.function)) catch return error.SubmissionIdentityLimit;
        const function: @import("../4_semantics/global/graph.zig").GlobalFunctionId = @enumFromInt(std.math.cast(u32, raw) orelse return error.SubmissionIdentityLimit);
        return .{ .candidate = try compiler.prepareContinuation(modules, diagnostics, function), .function = function };
    }

    const Parsed = struct {
        tree: @import("../3_syntax/syntax_tree.zig").FileSyntaxTree,
        code: []const u8,
        path: []const u8,
        dir: []const u8,
    };
    pub const SubmissionKind = enum { empty, definitions, statements, expression };

    /// Classification uses the language parser, never punctuation heuristics.
    /// Mixed module declarations and executable statements require separate
    /// submissions so their publication/execution boundary remains explicit.
    pub fn classify(self: *Sources, diagnostics: *diagnostics_mod.Diagnostics, source: []const u8) !SubmissionKind {
        var parsed = try self.parseSource(diagnostics, source, null);
        defer parsed.tree.deinit(self.allocator);
        if (parsed.tree.roots.len == 1) switch (parsed.tree.tag(parsed.tree.roots[0])) {
            .expression_statement, .function_call => return .expression,
            else => {},
        };
        var result: SubmissionKind = .empty;
        for (parsed.tree.roots) |root| {
            const is_import = if (parsed.tree.symbolDeclaration(root)) |declaration|
                if (declaration.value) |value| parsed.tree.tag(value) == .import_statement else false
            else
                false;
            const kind: SubmissionKind = if (is_import) .definitions else switch (parsed.tree.tag(root)) {
                .function_declaration, .function_declaration_once, .contract_declaration, .contract_conformance, .type_declaration, .c_struct_declaration, .c_incomplete_declaration, .c_enum_declaration, .c_union_declaration, .c_function_pointer_declaration, .choice_option_declaration => .definitions,
                else => .statements,
            };
            if (result != .empty and result != kind) {
                try diagnostics.add(parsed.tree.location(root), .semantic, "submit definitions separately from executable statements", .{});
                return error.Reported;
            }
            result = kind;
        }
        return result;
    }

    fn parseSource(self: *Sources, diagnostics: *diagnostics_mod.Diagnostics, source: []const u8, origin: ?SourceOrigin) !Parsed {
        if (diagnostics.hasErrors()) return error.Reported;
        if (self.sequence == std.math.maxInt(u64)) return error.SubmissionIdentityLimit;
        const sequence = self.sequence;
        self.sequence += 1;
        const retained = self.arena.allocator();
        const dir = try std.fmt.allocPrint(retained, "/__argi_session__/submission_{d}", .{sequence});
        const path = try std.fmt.allocPrint(retained, "{s}/main.rg", .{dir});
        return self.parseFile(diagnostics, source, origin, path, dir);
    }

    fn parseFile(self: *Sources, diagnostics: *diagnostics_mod.Diagnostics, source: []const u8, origin: ?SourceOrigin, path: []const u8, dir: []const u8) !Parsed {
        return self.parseSelectedFile(diagnostics, source, origin, path, dir, null);
    }

    fn parseSelectedFile(self: *Sources, diagnostics: *diagnostics_mod.Diagnostics, source: []const u8, origin: ?SourceOrigin, path: []const u8, dir: []const u8, target: ?@import("../1_base/target.zig").Config) !Parsed {
        const retained = self.arena.allocator();
        const code = try retained.dupe(u8, source);
        const file = try diagnostics.appendSource(.{ .path = path, .code = code });
        if (origin) |input| {
            const original = try diagnostics.appendSource(.{
                .path = try std.fmt.allocPrint(retained, "{s}/input.rg", .{dir}),
                .code = try retained.dupe(u8, input.text),
            });
            try diagnostics.addSourceMap(.{
                .generated = file,
                .original = original,
                .offset = std.math.cast(u32, input.offset) orelse return error.SubmissionIdentityLimit,
                .length = std.math.cast(u32, input.text.len) orelse return error.SubmissionIdentityLimit,
            });
        }
        var selected: ?selection_mod.Prepared = null;
        defer if (selected) |*selection| selection.deinit(self.allocator);
        const syntax = if (target) |config| blk: {
            var offset: usize = 0;
            selected = selection_mod.Prepared.init(self.allocator, code, config, &offset, .computed) catch |err| {
                if (err == error.OutOfMemory) return err;
                try diagnostics.add(.{ .file = file, .offset = @intCast(offset) }, .syntax, "invalid target selection: {s}", .{selection_mod.errorMessage(err)});
                return error.Reported;
            };
            break :blk (try selected.?.syntax(retained)).source;
        } else code;
        var tree = try self.parseSyntax(diagnostics, syntax, file);
        errdefer tree.deinit(self.allocator);
        if (selected) |selection| {
            try self.selections.put(self.allocator, file, selection);
            selected = null;
        }
        return .{ .tree = tree, .code = code, .path = path, .dir = dir };
    }

    fn parseSyntax(self: *Sources, diagnostics: *diagnostics_mod.Diagnostics, source: []const u8, file: FileId) !@import("../3_syntax/syntax_tree.zig").FileSyntaxTree {
        var tokens = @import("../2_tokens/tokenizer.zig").Tokenizer.init(self.allocator, diagnostics, source, file);
        defer tokens.deinit();
        _ = try tokens.tokenize();
        if (diagnostics.hasErrors()) return error.Reported;
        var parser = @import("../3_syntax/syntaxer.zig").Syntaxer.initFile(self.allocator, @import("../3_syntax/syntax_tree.zig").FileSyntaxTree.initOwnedTokens(file, tokens.takeTokens()), source, diagnostics);
        defer parser.deinit();
        var tree = try parser.parse();
        errdefer tree.deinit(self.allocator);
        if (diagnostics.hasErrors()) return error.Reported;
        return tree;
    }

    pub fn loadModule(self: *Sources, diagnostics: *diagnostics_mod.Diagnostics, source: []const u8) !*module_sg.ModuleSemanticGraph {
        return self.loadModuleOrigin(diagnostics, source, null);
    }

    fn loadModuleOrigin(self: *Sources, diagnostics: *diagnostics_mod.Diagnostics, source: []const u8, origin: ?SourceOrigin) !*module_sg.ModuleSemanticGraph {
        var parsed = try self.parseSource(diagnostics, source, origin);
        defer parsed.tree.deinit(self.allocator);
        const code = parsed.code;
        const path = parsed.path;
        const dir = parsed.dir;
        const tree = &parsed.tree;
        const inputs = [_]module_sg.FileInput{.{ .diagnostics = diagnostics, .path = path, .tree = tree, .source = code }};
        return self.finishModule(diagnostics, dir, &inputs, .{});
    }

    fn finishModule(self: *Sources, diagnostics: *diagnostics_mod.Diagnostics, dir: []const u8, inputs: []const module_sg.FileInput, target: @import("../1_base/target.zig").Config) !*module_sg.ModuleSemanticGraph {
        const graph = try self.allocator.create(module_sg.ModuleSemanticGraph);
        errdefer self.allocator.destroy(graph);
        graph.* = try module_sg.buildForTarget(self.allocator, dir, inputs, target);
        errdefer graph.deinit(self.allocator);
        _ = try @import("../4_semantics/module/semantizer.zig").finish(self.allocator, graph, inputs, diagnostics);
        if (diagnostics.hasErrors()) return error.Reported;
        try self.modules.append(self.allocator, graph);
        return graph;
    }

    /// Build dependency modules through the ordinary tokenizer, parser and
    /// ModuleSema. Only the accepted prefix determines which files are reused.
    pub fn loadImports(self: *Sources, diagnostics: *diagnostics_mod.Diagnostics, io: std.Io, importer_path: []const u8, source: []const u8, session: *sema.Session, target: @import("../1_base/target.zig").Config) !void {
        const sf = @import("../1_base/source_files.zig");
        const a = self.allocator;
        const dirs = try a.alloc([]const u8, session.modules.len);
        defer a.free(dirs);
        for (dirs, session.modules) |*dir, module| dir.* = module.module_dir;
        var files = try sf.collectImportedModules(&a, io, .{ .path = importer_path, .code = source }, dirs, .{ .target = target });
        defer sf.freeList(&a, &files);
        var start: usize = 0;
        while (start < files.items.len) {
            const dir = std.fs.path.dirname(files.items[start].path) orelse ".";
            var end = start + 1;
            while (end < files.items.len and std.mem.eql(u8, std.fs.path.dirname(files.items[end].path) orelse ".", dir)) : (end += 1) {}
            const parsed = try a.alloc(Parsed, end - start);
            defer a.free(parsed);
            var count: usize = 0;
            defer for (parsed[0..count]) |*file| file.tree.deinit(a);
            for (files.items[start..end], parsed) |file, *out| {
                const path = try self.arena.allocator().dupe(u8, file.path);
                const owned_dir = try self.arena.allocator().dupe(u8, dir);
                out.* = try self.parseSelectedFile(diagnostics, file.code, null, path, owned_dir, target);
                count += 1;
            }
            const inputs = try a.alloc(module_sg.FileInput, parsed.len);
            defer a.free(inputs);
            for (inputs, parsed) |*input, *file| input.* = .{ .diagnostics = diagnostics, .path = file.path, .tree = &file.tree, .source = file.code };
            const module = try self.finishModule(diagnostics, dir, inputs, target);
            try session.appendModules(try self.appendSnapshot(session.modules, module));
            start = end;
        }
    }

    /// Resolve newly loaded source choices through the same fixed-point driver
    /// used by CLI preparation. Already accepted module choices stay frozen.
    pub fn selectModules(self: *Sources, diagnostics: *diagnostics_mod.Diagnostics, session: *sema.Session, first_module: usize, io: std.Io, target: @import("../1_base/target.zig").Config) !void {
        var loader = SelectionLoader{ .sources = self, .diagnostics = diagnostics, .io = io, .target = target };
        try @import("../4_semantics/global/module_selection.zig").resolve(self.allocator, session, first_module, &loader);
    }

    const SelectionLoader = struct {
        sources: *Sources,
        diagnostics: *diagnostics_mod.Diagnostics,
        io: std.Io,
        target: @import("../1_base/target.zig").Config,

        pub fn materialize(self: *SelectionLoader, session: *sema.Session, module_index: usize, condition: module_sg.ModuleCondition, decision: bool) !void {
            const sources = self.sources;
            const a = sources.arena.allocator();
            const module = session.modules[module_index];
            const path = try std.fs.path.join(a, &.{ module.module_dir, module.text(module.file_offsets.items[condition.source.file_index].path) });
            const file = self.diagnostics.source_db.findVersion(path, module.file_offsets.items[condition.source.file_index].content_hash) orelse return error.InvalidModuleConditionSource;
            const selection = sources.selections.getPtr(file) orelse return error.InvalidModuleConditionSource;
            const branch = for (selection.plan.branches.items, 0..) |candidate, index| {
                if (candidate.extent.start == condition.source.offset) break @as(selection_mod.Prepared.BranchId, @enumFromInt(index));
            } else return error.InvalidModuleConditionSource;
            try selection.resolve(branch, decision);
            const rendered = try selection.fragment(a, branch, true);
            const imports = try selection.fragment(a, branch, false);
            try sources.loadImports(self.diagnostics, self.io, path, imports.source, session, self.target);
            var tree = try sources.parseSyntax(self.diagnostics, rendered.source, file);
            defer tree.deinit(sources.allocator);
            const input = module_sg.FileInput{ .diagnostics = self.diagnostics, .path = path, .tree = &tree, .source = self.diagnostics.source_files[@intFromEnum(file)].code, .is_bundled_core = module.is_bundled_core };
            const fragment = try sources.finishModule(self.diagnostics, module.module_dir, &.{input}, self.target);
            try session.appendModuleFragment(try sources.appendSnapshot(session.modules, fragment), @enumFromInt(module_index));
        }
    };

    /// Synthetic modules keep unique identities. Resolve their import spellings
    /// at the loader boundary against the real caller directory instead.
    pub fn resolveSubmissionImports(self: *Sources, graph: *module_sg.ModuleSemanticGraph, io: std.Io, importer_path: []const u8) !void {
        var writer = @import("../4_semantics/module/writer.zig").Writer.init(self.allocator, graph);
        for (graph.semantic.module_aliases.items) |*alias| {
            const spelling = std.mem.trim(u8, graph.text(alias.path), "\"'");
            const resolved = try @import("../1_base/source_files.zig").resolveImportDir(&self.allocator, io, importer_path, spelling);
            defer self.allocator.free(resolved);
            alias.path = try writer.addString(resolved);
        }
    }

    /// Extend an immutable prefix without copying every previous module header.
    /// Geometric buffers never relocate: old slices keep their length and only
    /// unused tail slots are written. Forking any older prefix allocates a new
    /// buffer, preserving both accepted and rejected candidates' borrowed views.
    pub fn appendSnapshot(self: *Sources, prefix: []const module_sg.ModuleSemanticGraph, module: *const module_sg.ModuleSemanticGraph) ![]const module_sg.ModuleSemanticGraph {
        const count = std.math.add(usize, prefix.len, 1) catch return error.SubmissionIdentityLimit;
        if (prefix.ptr == self.snapshot_tail.ptr and prefix.len == self.snapshot_len and count <= self.snapshot_tail.len) {
            self.snapshot_tail[prefix.len] = module.*;
            self.snapshot_len = count;
            return self.snapshot_tail[0..count];
        }
        const capacity = std.math.ceilPowerOfTwo(usize, @max(count, 4)) catch return error.SubmissionIdentityLimit;
        const snapshot = try self.arena.allocator().alloc(module_sg.ModuleSemanticGraph, capacity);
        @memcpy(snapshot[0..prefix.len], prefix);
        snapshot[prefix.len] = module.*;
        self.snapshot_tail = snapshot;
        self.snapshot_len = count;
        return snapshot[0..count];
    }
};

test "submission sources retain immutable modules and rejected source diagnostics" {
    const a = std.testing.allocator;
    var sources = Sources.init(a);
    defer sources.deinit();
    var diagnostic_arena = std.heap.ArenaAllocator.init(a);
    defer diagnostic_arena.deinit();
    const diagnostic_allocator = diagnostic_arena.allocator();
    var diagnostics = diagnostics_mod.Diagnostics.init(&diagnostic_allocator, &.{});
    defer diagnostics.deinit();
    const first = try sources.loadModule(&diagnostics, "first := () -> () {}\n");
    const prefix = try sources.appendSnapshot(&.{}, first);
    try std.testing.expect(first.semantic.local_semantics_complete);
    const original_dir = prefix[0].module_dir;
    _ = sources.loadModule(&diagnostics, "broken := () -> () {\n") catch {};
    try std.testing.expect(diagnostics.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), sources.modules.items.len);
    try std.testing.expectEqual(@as(usize, 2), diagnostics.source_files.len);
    diagnostics.list.clearRetainingCapacity();
    const second = try sources.loadModule(&diagnostics, "second := () -> () {}\n");
    const extended = try sources.appendSnapshot(prefix, second);
    try std.testing.expectEqual(@as(usize, 1), prefix.len);
    try std.testing.expectEqualStrings(original_dir, prefix[0].module_dir);
    try std.testing.expect(!std.mem.eql(u8, extended[0].module_dir, extended[1].module_dir));
    try std.testing.expectEqual(@as(usize, 3), diagnostics.source_files.len);
    try std.testing.expectEqual(@as(usize, 0), diagnostics.source_maps.len);
}

test "source submissions compile and execute incrementally without history replay" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sources = Sources.init(a);
    defer sources.deinit();
    var diagnostics = diagnostics_mod.Diagnostics.init(&a, &.{});
    defer diagnostics.deinit();
    var compiler = try @import("compilation_session.zig").CompilationSession.init(a, &.{}, .{ .exhaustive_function_bodies = false });
    defer compiler.deinit();
    var runtime = @import("session.zig").Session.init(a, &compiler, .{});
    defer runtime.deinit();
    var first = try sources.prepareCommand(&compiler, &diagnostics, "retained :: Int32 = 42");
    defer first.deinit();
    const binding = first.candidate.semantic.?.resolvers.expressions.session_bindings.items[0];
    try runtime.executeCommand(&first.candidate);
    try std.testing.expectError(error.DuplicateSessionBinding, sources.prepareCommand(&compiler, &diagnostics, "retained :: Int32 = 99"));
    try std.testing.expectEqual(@as(u64, 1), compiler.revision);
    try std.testing.expectEqual(@as(usize, 1), compiler.semantic.modules.len);
    var second = try sources.prepareCommand(&compiler, &diagnostics, "retained = 7");
    defer second.deinit();
    try runtime.executeCommand(&second.candidate);
    const stored = try runtime.context.storage.slots(runtime.context.bindings.get(binding).?);
    try std.testing.expectEqual(@as(i128, 7), (try stored.get(0)).integer);
    try std.testing.expectEqual(@as(usize, 3), sources.modules.items.len);
    try std.testing.expectEqual(@as(usize, 6), diagnostics.source_files.len);
    try std.testing.expectEqual(@as(usize, 3), diagnostics.source_maps.len);
    try std.testing.expectEqualStrings("retained = 7", diagnostics.source_db.get(diagnostics.source_maps[2].original).source);
    try std.testing.expectEqual(@as(u64, 2), compiler.revision);
}

test "submission snapshot growth shares prefixes without mutating earlier branches" {
    var sources = Sources.init(std.testing.allocator);
    defer sources.deinit();
    const first: module_sg.ModuleSemanticGraph = .{ .module_dir = "first" };
    const second: module_sg.ModuleSemanticGraph = .{ .module_dir = "second" };
    const alternate: module_sg.ModuleSemanticGraph = .{ .module_dir = "alternate" };
    const prefix = try sources.appendSnapshot(&.{}, &first);
    const extended = try sources.appendSnapshot(prefix, &second);
    try std.testing.expect(prefix.ptr == extended.ptr);
    const branch = try sources.appendSnapshot(prefix, &alternate);
    try std.testing.expect(branch.ptr != extended.ptr);
    try std.testing.expectEqualStrings("second", extended[1].module_dir);
    try std.testing.expectEqualStrings("alternate", branch[1].module_dir);
    var grown = branch;
    for (0..8) |_| grown = try sources.appendSnapshot(grown, &first);
    try std.testing.expect(grown.ptr != branch.ptr);
    try std.testing.expectEqual(@as(usize, 1), prefix.len);
    try std.testing.expectEqual(@as(usize, 2), branch.len);
    try std.testing.expectEqualStrings("alternate", branch[1].module_dir);
    try std.testing.expectEqualStrings("second", extended[1].module_dir);
    // Appending a discarded branch after growth cannot overwrite the current
    // history or its older prefix, even when a previous buffer has spare room.
    const resumed = try sources.appendSnapshot(extended, &second);
    try std.testing.expect(resumed.ptr != grown.ptr);
    try std.testing.expectEqualStrings("alternate", grown[1].module_dir);
    try std.testing.expectEqualStrings("second", resumed[1].module_dir);
}
