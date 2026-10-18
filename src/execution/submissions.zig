const std = @import("std");
const module_sg = @import("../4_semantics/module/graph.zig");
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

    pub fn init(allocator: std.mem.Allocator) Sources {
        return .{ .allocator = allocator, .arena = .init(allocator) };
    }
    pub fn deinit(self: *Sources) void {
        for (self.modules.items) |module| {
            module.deinit(self.allocator);
            self.allocator.destroy(module);
        }
        self.modules.deinit(self.allocator);
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
        var tokens = @import("../2_tokens/tokenizer.zig").Tokenizer.init(self.allocator, diagnostics, code, file);
        defer tokens.deinit();
        _ = try tokens.tokenize();
        if (diagnostics.hasErrors()) return error.Reported;
        var parser = @import("../3_syntax/syntaxer.zig").Syntaxer.initFile(self.allocator, @import("../3_syntax/syntax_tree.zig").FileSyntaxTree.initOwnedTokens(file, tokens.takeTokens()), code, diagnostics);
        defer parser.deinit();
        var tree = try parser.parse();
        errdefer tree.deinit(self.allocator);
        if (diagnostics.hasErrors()) return error.Reported;
        return .{ .tree = tree, .code = code, .path = path, .dir = dir };
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
    pub fn loadImports(self: *Sources, diagnostics: *diagnostics_mod.Diagnostics, io: std.Io, importer_path: []const u8, source: []const u8, prefix: []const module_sg.ModuleSemanticGraph, target: @import("../1_base/target.zig").Config) ![]const module_sg.ModuleSemanticGraph {
        const sf = @import("../1_base/source_files.zig");
        const a = self.allocator;
        const dirs = try a.alloc([]const u8, prefix.len);
        defer a.free(dirs);
        for (dirs, prefix) |*dir, module| dir.* = module.module_dir;
        var files = try sf.collectImportedModules(&a, io, .{ .path = importer_path, .code = source }, dirs, .{ .target = target });
        defer sf.freeList(&a, &files);
        const first_module = self.modules.items.len;
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
                out.* = try self.parseFile(diagnostics, file.code, null, path, owned_dir);
                count += 1;
            }
            const inputs = try a.alloc(module_sg.FileInput, parsed.len);
            defer a.free(inputs);
            for (inputs, parsed) |*input, *file| input.* = .{ .diagnostics = diagnostics, .path = file.path, .tree = &file.tree, .source = file.code };
            _ = try self.finishModule(diagnostics, dir, inputs, target);
            start = end;
        }
        const added = self.modules.items[first_module..];
        if (added.len == 0) return prefix;
        const count = std.math.add(usize, prefix.len, added.len) catch return error.SubmissionIdentityLimit;
        const snapshot = try self.arena.allocator().alloc(module_sg.ModuleSemanticGraph, count);
        @memcpy(snapshot[0..prefix.len], prefix);
        for (snapshot[prefix.len..], added) |*out, module| out.* = module.*;
        return snapshot;
    }

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

    /// Each snapshot is immutable and independently allocated; growth of the
    /// source owner cannot invalidate a semantic session's borrowed prefix.
    pub fn appendSnapshot(self: *Sources, prefix: []const module_sg.ModuleSemanticGraph, module: *const module_sg.ModuleSemanticGraph) ![]const module_sg.ModuleSemanticGraph {
        const count = std.math.add(usize, prefix.len, 1) catch return error.SubmissionIdentityLimit;
        const snapshot = try self.arena.allocator().alloc(module_sg.ModuleSemanticGraph, count);
        @memcpy(snapshot[0..prefix.len], prefix);
        snapshot[prefix.len] = module.*;
        return snapshot;
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
