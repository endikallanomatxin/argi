const std = @import("std");
const submissions = @import("submissions.zig");
const compilation = @import("compilation_session.zig");
const execution = @import("session.zig");
const diagnostics_mod = @import("../1_base/diagnostic.zig");
const module_sg = @import("../4_semantics/module/graph.zig");
const sema = @import("../4_semantics/global/semantizer.zig");
const vm = @import("vm.zig");

/// High-level retained execution owner used by interactive frontends. Initialize
/// in final storage: diagnostics and runtime borrow fields at stable addresses.
/// Initial module graphs remain borrowed; submitted sources are owned here.
/// Explicit close/reset executes checked cleanup; deinit only frees host memory.
pub const Interactive = struct {
    allocator: std.mem.Allocator,
    diagnostic_arena: std.heap.ArenaAllocator,
    diagnostic_allocator: std.mem.Allocator,
    diagnostics: diagnostics_mod.Diagnostics,
    sources: submissions.Sources,
    compiler: compilation.CompilationSession,
    runtime: execution.Session,
    initial_modules: []const module_sg.ModuleSemanticGraph,
    options: sema.Options,
    limits: vm.Limits,
    closed: bool = false,

    pub fn init(self: *Interactive, allocator: std.mem.Allocator, modules: []const module_sg.ModuleSemanticGraph, options: sema.Options, limits: vm.Limits) !void {
        self.allocator = allocator;
        self.initial_modules = modules;
        self.options = options;
        self.limits = limits;
        self.closed = false;
        self.diagnostic_arena = .init(allocator);
        errdefer self.diagnostic_arena.deinit();
        self.diagnostic_allocator = self.diagnostic_arena.allocator();
        self.diagnostics = .init(&self.diagnostic_allocator, &.{});
        errdefer self.diagnostics.deinit();
        self.sources = .init(allocator);
        errdefer self.sources.deinit();
        var selected = options;
        selected.diagnostics = &self.diagnostics;
        self.compiler = try compilation.CompilationSession.init(allocator, modules, selected);
        self.runtime = .init(allocator, &self.compiler, limits);
    }
    pub fn deinit(self: *Interactive) void {
        self.runtime.deinit();
        self.compiler.deinit();
        self.diagnostics.deinit();
        self.sources.deinit();
        self.diagnostic_arena.deinit();
        self.* = undefined;
    }

    pub fn submitStatements(self: *Interactive, statements: []const u8) !void {
        try self.beginSubmission();
        var command = try self.sources.prepareCommand(&self.compiler, &self.diagnostics, statements);
        defer command.deinit();
        try self.runtime.executeCommand(&command.candidate);
    }
    fn beginSubmission(self: *Interactive) !void {
        if (self.closed) return error.InteractiveSessionClosed;
        if (self.runtime.context.state == .poisoned) return error.ExecutionContextPoisoned;
        self.diagnostics.list.clearRetainingCapacity();
    }

    pub fn close(self: *Interactive) !void {
        try self.beginSubmission();
        try self.cleanup();
        self.closed = true;
    }
    fn cleanup(self: *Interactive) !void {
        const command = try self.sources.loadCommand(&self.diagnostics, "");
        const prefix = try self.sources.appendSnapshot(self.compiler.semantic.modules, command.module);
        const base = self.compiler.semantic.relocation.graph.functions.items.len;
        const raw = try std.math.add(usize, base, @intFromEnum(command.function));
        const entry: @import("../4_semantics/global/graph.zig").GlobalFunctionId = @enumFromInt(std.math.cast(u32, raw) orelse return error.SubmissionIdentityLimit);
        var candidate = try self.compiler.prepareExit(prefix, &self.diagnostics, entry, self.compiler.semantic.resolvers.expressions.session_bindings.items);
        defer candidate.deinit();
        try self.runtime.executeCommand(&candidate);
    }

    pub fn reset(self: *Interactive) !void {
        if (self.closed) return error.InteractiveSessionClosed;
        // Allocate the replacement first: failure cannot discard live owners.
        var options = self.options;
        options.diagnostics = &self.diagnostics;
        var replacement = try compilation.CompilationSession.init(self.allocator, self.initial_modules, options);
        errdefer replacement.deinit();
        if (self.runtime.context.state != .poisoned) {
            self.diagnostics.list.clearRetainingCapacity();
            try self.cleanup();
        }
        // A trapped context has no safe user-code unwind. Its explicit reset
        // discards the poisoned execution and proof state together.
        self.runtime.deinit();
        self.compiler.deinit();
        self.compiler = replacement;
        self.runtime = .init(self.allocator, &self.compiler, self.limits);
        self.diagnostics.list.clearRetainingCapacity();
    }
};

test "interactive controller retains statements recovers rejected input and resets" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitStatements("value :: Int32 = 42");
    const original_namespace = session.compiler.namespace;
    try std.testing.expectError(error.DuplicateSessionBinding, session.submitStatements("value :: Int32 = 99"));
    try session.submitStatements("value = 7");
    const binding = session.compiler.semantic.resolvers.expressions.session_bindings.items[0];
    const stored = try session.runtime.context.storage.slots(session.runtime.context.bindings.get(binding).?);
    try std.testing.expectEqual(@as(i128, 7), (try stored.get(0)).integer);
    try session.reset();
    try std.testing.expect(session.compiler.namespace != original_namespace);
    try std.testing.expectEqual(@as(usize, 0), session.compiler.semantic.resolvers.expressions.session_bindings.items.len);
    try session.submitStatements("value :: Int32 = 12");
    try session.close();
    try std.testing.expectEqual(.fresh, session.runtime.context.state);
    try std.testing.expectError(error.InteractiveSessionClosed, session.submitStatements("value = 1"));
}

test "interactive controller recovers poisoned contexts by reset" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{ .instructions = 30 });
    defer session.deinit();
    try session.submitStatements("value ::= 42");
    try std.testing.expectError(error.ExecutionInstructionLimit, session.submitStatements("while true {}"));
    try std.testing.expectError(error.ExecutionContextPoisoned, session.submitStatements("value = 7"));
    try std.testing.expectError(error.ExecutionContextPoisoned, session.close());
    try session.reset();
    try session.submitStatements("fresh ::= 7");
    try session.close();
}
