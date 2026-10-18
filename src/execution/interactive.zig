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
    pub fn submitDefinitions(self: *Interactive, source: []const u8) !void {
        try self.beginSubmission();
        const module = try self.sources.loadModule(&self.diagnostics, source);
        const prefix = try self.sources.appendSnapshot(self.compiler.semantic.modules, module);
        var candidate = try self.compiler.prepareDefinitions(prefix, &self.diagnostics);
        defer candidate.deinit();
        try self.compiler.accept(&candidate);
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

test "interactive definitions remain visible to subsequent definitions and statements" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("answer := () -> (.result: Int32) { result = 42 }\n");
    try session.submitDefinitions("forward := () -> (.result: Int32) { result = answer() }\n");
    try session.submitStatements("value ::= forward()");
    try session.submitStatements("other ::= value");
    try session.submitDefinitions("later := () -> (.result: Int32) { result = answer() }\n");
    try session.submitDefinitions("identity#(.T: Type) := (.value: T) -> (.result: T) { result = value }\n");
    try session.submitStatements("generic_value ::= identity#(Int32)(.value = later())");
    const binding = session.compiler.semantic.resolvers.expressions.session_bindings.items[0];
    const stored = try session.runtime.context.storage.slots(session.runtime.context.bindings.get(binding).?);
    try std.testing.expectEqual(@as(i128, 42), (try stored.get(0)).integer);
    const generic_binding = session.compiler.semantic.resolvers.expressions.session_bindings.items[2];
    const generic_stored = try session.runtime.context.storage.slots(session.runtime.context.bindings.get(generic_binding).?);
    try std.testing.expectEqual(@as(i128, 42), (try generic_stored.get(0)).integer);
    const revision = session.compiler.revision;
    try std.testing.expectError(error.DuplicateSessionDeclaration, session.submitDefinitions("answer := () -> (.result: Int32) { result = 7 }\n"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try std.testing.expectError(error.DuplicateSessionDeclaration, session.submitStatements("answer ::= 7"));
    try std.testing.expectEqual(revision, session.compiler.revision);
    // Loading an ordinary module must not grant the interactive namespace.
    const isolated = try session.sources.loadModule(&session.diagnostics, "outside := () -> (.result: Int32) { result = answer() }\n");
    const prefix = try session.sources.appendSnapshot(session.compiler.semantic.modules, isolated);
    var ordinary = try session.compiler.prepare(prefix, &session.diagnostics);
    defer ordinary.deinit();
    const core = &ordinary.semantic.?.resolvers.core;
    try std.testing.expect(!core.sameDeclarationNamespace(0, core.modules.len - 1));
    try std.testing.expect(core.sameDeclarationNamespace(0, 1));
    const declaration = for (core.session_namespace.?.declarations.items) |decl| {
        if (std.mem.eql(u8, core.graph.text(core.graph.declaration(decl).name), "answer")) break decl;
    } else return error.MissingDeclaration;
    try std.testing.expect(!core.declarationVisible(core.modules.len - 1, declaration, null));
    const later = for (core.session_namespace.?.declarations.items) |decl| {
        if (std.mem.eql(u8, core.graph.text(core.graph.declaration(decl).name), "later")) break decl;
    } else return error.MissingDeclaration;
    // Deferred specialization of an earlier definition cannot acquire names
    // introduced by a future submission merely because it materializes later.
    try std.testing.expect(!core.declarationVisible(0, later, null));
    try std.testing.expectEqual(revision, session.compiler.revision);
    try session.close();
}

test "interactive contract definitions select implementations in later submissions" {
    var session: Interactive = undefined;
    try session.init(std.testing.allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
    defer session.deinit();
    try session.submitDefinitions("Echo#(.T: Type): Contract = (.echo: (.value: T) -> (.result: T))\n");
    session.submitDefinitions("implement Echo#(Int32) (.echo = (.value: Int32) -> (.result: Int32) { result = value })\n") catch |err| {
        try session.diagnostics.dump();
        return err;
    };
    // Identical source offsets in different submissions must not make private
    // implementation-body identities collide in the source namespace.
    try session.submitDefinitions("implement Echo#(Int64) (.echo = (.value: Int64) -> (.result: Int64) { result = value })\n");
    try session.submitStatements("value ::= echo(.value = 42)");
    const binding = session.compiler.semantic.resolvers.expressions.session_bindings.items[0];
    const stored = try session.runtime.context.storage.slots(session.runtime.context.bindings.get(binding).?);
    try std.testing.expectEqual(@as(i128, 42), (try stored.get(0)).integer);
    try session.close();
}
