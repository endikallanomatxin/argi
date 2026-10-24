const std = @import("std");
const compilation = @import("compilation_session.zig");
const execution = @import("vm.zig");
const bytecode = @import("../5_codegen/bytecode/bytecode.zig");
const graph = @import("../4_semantics/global/graph.zig");
const profile = @import("../1_base/profile.zig");

/// Optional retained-session measurements; ordinary AOT paths never use these.
/// Verification includes host-binding validation performed by VM initialization.
pub const Stats = struct {
    lowering_ns: u64 = 0,
    verification_ns: u64 = 0,
    execution_ns: u64 = 0,
    compiled_functions: usize = 0,
    compiled_instructions: usize = 0,
};

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
    profile_io: ?std.Io = null,
    stats: Stats = .{},

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

    /// Derive layouts from the exact candidate graph and accepted direct names.
    /// Temporary layout allocations die after execute copies them into its unit.
    pub fn executeCommand(self: *Session, candidate: *compilation.CompilationSession.Candidate) !void {
        const semantic = candidate.semantic orelse return error.StaleCompilationCandidate;
        const checked = candidate.checked orelse return error.StaleCompilationCandidate;
        const function = candidate.entry orelse return error.InvalidCommand;
        var scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer scratch.deinit();
        const layout_start = profile.timestamp(self.profile_io);
        const bindings = try @import("../5_codegen/bytecode/session_layout.zig").build(scratch.allocator(), checked.graph, semantic.resolvers.expressions.session_bindings.items);
        profile.accumulate(self.profile_io, layout_start, &self.stats.lowering_ns);
        if (candidate.is_exit) return self.executeExit(candidate, function, bindings);
        return self.execute(candidate, function, bindings);
    }

    pub fn execute(self: *Session, candidate: *compilation.CompilationSession.Candidate, function: graph.GlobalFunctionId, bindings: []const bytecode.SessionBinding) !void {
        if (self.context.state == .poisoned) return error.ExecutionContextPoisoned;
        if (self.context.running) return error.ExecutionContextBusy;
        if (candidate.owner != self.compiler or candidate.revision != self.compiler.revision or candidate.checked == null or candidate.semantic == null)
            return error.StaleCompilationCandidate;
        const checked = candidate.checked.?.graph;
        if (@intFromEnum(function) >= checked.functions.items.len) return error.InvalidEntry;
        const command = checked.function(function);
        if (command.input.len != 0 or command.output.len != 0 or candidate.temporal == null or candidate.entry != function) return error.InvalidCommand;
        const lower_start = profile.timestamp(self.profile_io);
        const arena = try self.allocator.create(std.heap.ArenaAllocator);
        arena.* = .init(self.allocator);
        var published = false;
        defer if (!published) {
            arena.deinit();
            self.allocator.destroy(arena);
        };
        const a = arena.allocator();
        var lowering_scratch = std.heap.ArenaAllocator.init(self.allocator);
        defer lowering_scratch.deinit();
        var lower = try @import("../5_codegen/bytecode/lower.zig").Lower.init(a, checked, .{ .session = .{ .namespace = self.compiler.namespace, .bindings = bindings }, .scratch_allocator = lowering_scratch.allocator() });
        lower.annotations = &candidate.checked.?.annotations;
        const diagnostics = candidate.semantic.?.options.diagnostics orelse return error.MissingSessionDiagnostics;
        lower.diagnostics = diagnostics;
        const program = lower.compile(function) catch |err| {
            if (err == error.UnsupportedExecution) {
                try diagnostics.add(@import("../4_semantics/global/source_location.zig").location(checked, diagnostics, lower.source), .codegen, "bytecode execution does not support {s}", .{lower.unsupported});
                return error.Reported;
            }
            return err;
        };
        _ = lowering_scratch.reset(.free_all);
        profile.accumulate(self.profile_io, lower_start, &self.stats.lowering_ns);
        if (self.profile_io != null) for (program.functions) |function_| {
            self.stats.compiled_functions += 1;
            self.stats.compiled_instructions += function_.body.code.len;
        };
        const verify_start = profile.timestamp(self.profile_io);
        var vm = execution.Vm.initShared(self.allocator, program, self.limits, &self.context) catch |err| {
            switch (err) {
                error.MissingHostBinding, error.IncompatibleHostBinding, error.AmbiguousHostBinding => {
                    const host = @import("host.zig");
                    const failure = host.findFailure(program, self.context.host_bindings) orelse return err;
                    try diagnostics.add(@import("../4_semantics/global/source_location.zig").location(checked, diagnostics, failure.source), .codegen, "bytecode host binding for '{s}' is unavailable: {s}", .{ host.symbol(checked, failure.function), @errorName(failure.reason) });
                    return error.Reported;
                },
                else => return err,
            }
        };
        profile.accumulate(self.profile_io, verify_start, &self.stats.verification_ns);
        defer vm.deinit();
        try self.units.ensureUnusedCapacity(self.allocator, 1);
        try self.compiler.accept(candidate);
        self.units.appendAssumeCapacity(arena);
        published = true;
        // After publication the unit and graph belong to their retained owners,
        // even when this invocation traps and poisons the execution context.
        const execute_start = profile.timestamp(self.profile_io);
        defer profile.accumulate(self.profile_io, execute_start, &self.stats.execution_ns);
        _ = vm.invoke(function, &.{}) catch |err| {
            if (err == error.OutOfMemory) return err;
            try @import("failure.zig").report(self.allocator, diagnostics, &vm, checked, "bytecode execution failed", err);
            return err;
        };
    }

    pub fn executeExit(self: *Session, candidate: *compilation.CompilationSession.Candidate, function: graph.GlobalFunctionId, bindings: []const bytecode.SessionBinding) !void {
        if (!candidate.is_exit) return error.InvalidExitCommand;
        try self.execute(candidate, function, bindings);
        // An incomplete binding list must not silently discard active owners.
        var iterator = self.context.bindings.valueIterator();
        while (iterator.next()) |frame| {
            const stored = &self.context.storage.frames.items[@intFromEnum(frame.*)];
            _ = try self.context.storage.slots(frame.*);
            if (std.mem.indexOfScalar(bool, stored.cleanup_flags, true) != null) {
                self.context.state = .poisoned;
                return error.ExecutionActiveCleanup;
            }
        }
        self.context.reset();
    }
};
