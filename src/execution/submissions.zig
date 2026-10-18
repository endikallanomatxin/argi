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

    pub fn loadModule(self: *Sources, diagnostics: *diagnostics_mod.Diagnostics, source: []const u8) !*const module_sg.ModuleSemanticGraph {
        if (diagnostics.hasErrors()) return error.Reported;
        if (self.sequence == std.math.maxInt(u64)) return error.SubmissionIdentityLimit;
        const sequence = self.sequence;
        self.sequence += 1;
        const retained = self.arena.allocator();
        const dir = try std.fmt.allocPrint(retained, "/__argi_session__/submission_{d}", .{sequence});
        const path = try std.fmt.allocPrint(retained, "{s}/main.rg", .{dir});
        const code = try retained.dupe(u8, source);
        const file = try diagnostics.appendSource(.{ .path = path, .code = code });
        var tokens = @import("../2_tokens/tokenizer.zig").Tokenizer.init(self.allocator, diagnostics, code, file);
        defer tokens.deinit();
        _ = try tokens.tokenize();
        if (diagnostics.hasErrors()) return error.Reported;
        var parser = @import("../3_syntax/syntaxer.zig").Syntaxer.initFile(self.allocator, @import("../3_syntax/syntax_tree.zig").FileSyntaxTree.initOwnedTokens(file, tokens.takeTokens()), code, diagnostics);
        defer parser.deinit();
        var tree = try parser.parse();
        defer tree.deinit(self.allocator);
        if (diagnostics.hasErrors()) return error.Reported;
        const inputs = [_]module_sg.FileInput{.{ .diagnostics = diagnostics, .path = path, .tree = &tree, .source = code }};
        const graph = try self.allocator.create(module_sg.ModuleSemanticGraph);
        errdefer self.allocator.destroy(graph);
        graph.* = try module_sg.build(self.allocator, dir, &inputs);
        errdefer graph.deinit(self.allocator);
        _ = try @import("../4_semantics/module/semantizer.zig").finish(self.allocator, graph, &inputs, diagnostics);
        if (diagnostics.hasErrors()) return error.Reported;
        try self.modules.append(self.allocator, graph);
        return graph;
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
    const first = try sources.loadModule(&diagnostics, "command := () -> () { retained :: Int32 = 42 }\n");
    const first_prefix = try sources.appendSnapshot(&.{}, first);
    var command = try compiler.prepareContinuation(first_prefix, &diagnostics, @enumFromInt(0));
    defer command.deinit();
    const binding = command.semantic.?.resolvers.expressions.session_bindings.items[0];
    const layouts = [_]@import("../5_codegen/bytecode/bytecode.zig").SessionBinding{.{ .binding = binding, .slots = &.{command.checked.?.graph.binding(binding).ty} }};
    try runtime.execute(&command, @enumFromInt(0), &layouts);
    const second = try sources.loadModule(&diagnostics, "update := () -> () { retained = 7 }\n");
    const extended = try sources.appendSnapshot(first_prefix, second);
    const next: @import("../4_semantics/global/graph.zig").GlobalFunctionId = @enumFromInt(first.functions.items.len);
    var update = try compiler.prepareContinuation(extended, &diagnostics, next);
    defer update.deinit();
    try runtime.execute(&update, next, &layouts);
    const stored = try runtime.context.storage.slots(runtime.context.bindings.get(binding).?);
    try std.testing.expectEqual(@as(i128, 7), (try stored.get(0)).integer);
    try std.testing.expectEqual(@as(usize, 2), sources.modules.items.len);
    try std.testing.expectEqual(@as(usize, 2), diagnostics.source_files.len);
    try std.testing.expectEqual(@as(u64, 2), compiler.revision);
}
