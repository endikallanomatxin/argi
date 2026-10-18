const std = @import("std");
const compilation = @import("compilation_session.zig");
const execution = @import("vm.zig");
const bytecode = @import("../5_codegen/bytecode/bytecode.zig");
const graph = @import("../4_semantics/global/graph.zig");

/// Executes checked command candidates against one persistent context. The
/// compilation owner must remain at its final address and outlive this owner.
/// Preparation failures publish nothing. Once execution starts, ordinary writes
/// remain visible; a trap poisons the context rather than promising rollback.
pub const Session = struct {
    allocator: std.mem.Allocator,
    compiler: *compilation.CompilationSession,
    context: execution.Context,
    limits: execution.Limits,
    units: std.ArrayList(*std.heap.ArenaAllocator) = .empty,

    pub fn init(allocator: std.mem.Allocator, compiler: *compilation.CompilationSession, limits: execution.Limits) Session {
        return .{ .allocator = allocator, .compiler = compiler, .context = .init(allocator, limits.value_cells), .limits = limits };
    }
    pub fn deinit(self: *Session) void {
        // Language cleanup is an explicit checked exit, never Zig destruction.
        self.context.deinit();
        for (self.units.items) |arena| {
            arena.deinit();
            self.allocator.destroy(arena);
        }
        self.units.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn execute(self: *Session, candidate: *compilation.CompilationSession.Candidate, function: graph.GlobalFunctionId, bindings: []const bytecode.SessionBinding) !void {
        if (self.context.state == .poisoned) return error.ExecutionContextPoisoned;
        if (self.context.running) return error.ExecutionContextBusy;
        if (candidate.owner != self.compiler or candidate.revision != self.compiler.revision or candidate.checked == null or candidate.semantic == null)
            return error.StaleCompilationCandidate;
        const checked = &candidate.checked.?.graph;
        if (@intFromEnum(function) >= checked.functions.items.len) return error.InvalidEntry;
        const command = checked.function(function);
        if (command.input.len != 0 or command.output.len != 0 or candidate.temporal == null or candidate.entry != function) return error.InvalidCommand;
        const arena = try self.allocator.create(std.heap.ArenaAllocator);
        arena.* = .init(self.allocator);
        var published = false;
        defer if (!published) {
            arena.deinit();
            self.allocator.destroy(arena);
        };
        const a = arena.allocator();
        const retained = try a.alloc(bytecode.SessionBinding, bindings.len);
        for (retained, bindings) |*out, binding| {
            out.* = binding;
            out.slots = try a.dupe(bytecode.Type, binding.slots);
            const cleanup = try a.dupe(bytecode.Cleanup, binding.cleanup);
            for (cleanup) |*entry| entry.path = try a.dupe(@import("../5_codegen/bytecode/value.zig").Projection, entry.path);
            out.cleanup = cleanup;
        }
        var lower = try @import("../5_codegen/bytecode/lower.zig").Lower.initSession(a, checked, .{ .namespace = self.compiler.namespace, .bindings = retained });
        const program = try lower.compile(function);
        var vm = try execution.Vm.initShared(self.allocator, program, self.limits, &self.context);
        defer vm.deinit();
        try self.units.ensureUnusedCapacity(self.allocator, 1);
        try self.compiler.accept(candidate);
        self.units.appendAssumeCapacity(arena);
        published = true;
        // After publication the unit and graph belong to their retained owners,
        // even when this invocation traps and poisons the execution context.
        _ = try vm.invoke(function, &.{});
    }

    pub fn executeExit(self: *Session, candidate: *compilation.CompilationSession.Candidate, function: graph.GlobalFunctionId, bindings: []const bytecode.SessionBinding) !void {
        if (!candidate.is_exit) return error.InvalidExitCommand;
        try self.execute(candidate, function, bindings);
        // An incomplete binding list must not silently discard active owners.
        var iterator = self.context.bindings.valueIterator();
        while (iterator.next()) |frame| {
            const stored = &self.context.storage.frames.items[@intFromEnum(frame.*)];
            const slots = try self.context.storage.slots(frame.*);
            for (stored.cleanup) |entry| if ((try slots.get(entry.flag)).boolean) {
                self.context.state = .poisoned;
                return error.ExecutionActiveCleanup;
            };
        }
        self.context.reset();
    }
};
