const std = @import("std");
const interactive = @import("execution/interactive.zig");
const sf = @import("1_base/source_files.zig");
const diagnostics_mod = @import("1_base/diagnostic.zig");
const frontend = @import("0_commands/frontend_pipeline.zig");

// Counts requested backing bytes still owned by the session, including arena
// slabs. These are not RSS or cumulative allocation traffic. Single-threaded
// preparation keeps attribution deterministic without production instrumentation.
const Memory = struct {
    child: std.mem.Allocator = std.heap.page_allocator,
    live: usize = 0,
    peak: usize = 0,
    limit: usize,

    fn allocator(self: *Memory) std.mem.Allocator {
        return .{ .ptr = self, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn canGrow(self: *Memory, old: usize, new: usize) bool {
        return new <= old or new - old <= self.limit -| self.live;
    }
    fn account(self: *Memory, old: usize, new: usize) void {
        self.live = self.live - old + new;
        self.peak = @max(self.peak, self.live);
    }
    fn alloc(ctx: *anyopaque, len: usize, alignment: std.mem.Alignment, ret: usize) ?[*]u8 {
        const self: *Memory = @ptrCast(@alignCast(ctx));
        if (!self.canGrow(0, len)) return null;
        const result = self.child.rawAlloc(len, alignment, ret) orelse return null;
        self.account(0, len);
        return result;
    }
    fn resize(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) bool {
        const self: *Memory = @ptrCast(@alignCast(ctx));
        if (!self.canGrow(memory.len, len) or !self.child.rawResize(memory, alignment, len, ret)) return false;
        self.account(memory.len, len);
        return true;
    }
    fn remap(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, len: usize, ret: usize) ?[*]u8 {
        const self: *Memory = @ptrCast(@alignCast(ctx));
        if (!self.canGrow(memory.len, len)) return null;
        const result = self.child.rawRemap(memory, alignment, len, ret) orelse return null;
        self.account(memory.len, len);
        return result;
    }
    fn free(ctx: *anyopaque, memory: []u8, alignment: std.mem.Alignment, ret: usize) void {
        const self: *Memory = @ptrCast(@alignCast(ctx));
        self.child.rawFree(memory, alignment, ret);
        self.account(memory.len, 0);
    }
};

const Scenario = enum { update, bindings, calls };

fn elapsed(io: std.Io, start: i96) u64 {
    return @intCast(@max(0, std.Io.Timestamp.now(io, .boot).nanoseconds - start));
}
fn ms(value: u64) f64 {
    return @as(f64, @floatFromInt(value)) / 1_000_000;
}
fn mib(value: usize) f64 {
    return @as(f64, @floatFromInt(value)) / (1024 * 1024);
}

fn report(session: *interactive.Interactive, memory: *Memory, scenario: Scenario, core: bool, commands: usize, total_ns: u64) !void {
    const stats = session.runtime.stats;
    const backend_ns = stats.lowering_ns + stats.verification_ns + stats.execution_ns;
    var checked_graphs: usize = 0;
    for (session.compiler.versions.items) |version| checked_graphs += version.graph.storageBytes();
    var code: usize = 0;
    for (session.runtime.units.items) |arena| code += arena.queryCapacity();
    var proofs: usize = 0;
    var proof = session.compiler.temporal;
    while (proof) |entry| : (proof = entry.parent) proofs += entry.arena.queryCapacity();
    for (session.compiler.versions.items) |version| if (version.safety_arena) |arena| {
        proofs += arena.queryCapacity();
    };
    var dead_frames: usize = 0;
    if (session.runtime.context.state != .fresh) {
        for (session.runtime.context.storage.frames.items) |frame| {
            if (!frame.alive) dead_frames += 1;
        }
    }
    const runtime = if (session.runtime.context.state == .fresh) 0 else session.runtime.context.arena.queryCapacity();
    std.debug.print("{s},{s},{d},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d},{d},{d},{d}\n", .{
        @tagName(scenario),          if (core) @as([]const u8, "core") else "minimal", commands,
        ms(total_ns),                ms(total_ns -| backend_ns),                       ms(stats.lowering_ns),
        ms(stats.verification_ns),   ms(stats.execution_ns),                           mib(memory.live),
        mib(memory.peak),            mib(checked_graphs),                              mib(code),
        mib(proofs),                 mib(session.sources.arena.queryCapacity()),       mib(session.diagnostic_arena.queryCapacity()),
        runtime,                     dead_frames,                                      stats.compiled_functions,
        stats.compiled_instructions,
    });
    // Check the actual retained value without adding a measurement submission.
    const bindings = session.compiler.semantic.resolvers.expressions.session_bindings.items;
    const frame = session.runtime.context.bindings.get(bindings[bindings.len - 1]) orelse return error.MissingBenchmarkBinding;
    const slots = try session.runtime.context.storage.slots(frame);
    if ((try slots.get(0)).integer != 42) return error.InvalidBenchmarkResult;
}

fn run(io: std.Io, count: usize, core: bool, scenario: Scenario, limit: usize) !void {
    var memory: Memory = .{ .limit = limit };
    const allocator = memory.allocator();
    {
        var initial_arena = std.heap.ArenaAllocator.init(allocator);
        defer initial_arena.deinit();
        const a = initial_arena.allocator();
        var session: interactive.Interactive = undefined;
        if (core) {
            const files = try sf.collectCoreWithOptions(&a, io, .{ .fallback_core_dir = "core" });
            const diagnostics = try a.create(diagnostics_mod.Diagnostics);
            diagnostics.* = .init(&a, files.items);
            const pipeline = try a.create(frontend.FrontendPipeline);
            pipeline.* = .init(a, io, diagnostics, .{ .module_jobs = 1 });
            const prepared = pipeline.prepareSessionFiles(files.items) catch |err| {
                try diagnostics.dump();
                return err;
            };
            try session.initPrepared(allocator, diagnostics.source_files, prepared, .{});
        } else try session.init(allocator, &.{}, .{ .exhaustive_function_bodies = false }, .{});
        defer session.deinit();
        if (scenario == .calls) try session.submitDefinitions("identity := (.value: Int32) -> (.result: Int32) { result = value }");
        try session.submitStatements("value :: Int32 = 42");
        session.runtime.profile_io = io;
        session.runtime.stats = .{};
        var total_ns: u64 = 0;
        try report(&session, &memory, scenario, core, 0, total_ns);
        for (1..count + 1) |index| {
            const source = switch (scenario) {
                .update => try allocator.dupe(u8, "value = 42"),
                .calls => try allocator.dupe(u8, "value = identity(.value = 42)"),
                .bindings => try std.fmt.allocPrint(allocator, "value_{d} :: Int32 = 42", .{index}),
            };
            defer allocator.free(source);
            const start = std.Io.Timestamp.now(io, .boot).nanoseconds;
            session.submitStatements(source) catch |err| {
                std.debug.print("Stopped after {d} commands: {s}; retained {d:.3} MiB, peak {d:.3} MiB\n", .{ index - 1, @errorName(err), mib(memory.live), mib(memory.peak) });
                try session.diagnostics.dump();
                return err;
            };
            total_ns += elapsed(io, start);
            if (index == 10 or index == 100 or index == 1000 or index == count) try report(&session, &memory, scenario, core, index, total_ns);
        }
        // Snapshot before cleanup; include neither reset nor teardown in timings.
        try session.close();
    }
    if (memory.live != 0) {
        std.debug.print("Benchmark teardown retained {d} requested bytes\n", .{memory.live});
        return error.BenchmarkMemoryLeak;
    }
}

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len > 5) return error.InvalidArguments;
    const count = if (args.len >= 2) try std.fmt.parseInt(usize, args[1], 10) else 1000;
    if (count == 0 or count == std.math.maxInt(usize)) return error.InvalidArguments;
    const core = if (args.len >= 3) blk: {
        if (std.mem.eql(u8, args[2], "core")) break :blk true;
        if (std.mem.eql(u8, args[2], "minimal")) break :blk false;
        return error.InvalidArguments;
    } else false;
    const scenario = if (args.len >= 4) std.meta.stringToEnum(Scenario, args[3]) orelse return error.InvalidArguments else .update;
    const memory_mib = if (args.len >= 5) try std.fmt.parseInt(usize, args[4], 10) else 2048;
    const limit = try std.math.mul(usize, memory_mib, 1024 * 1024);
    std.debug.print("# [commands=1000] [minimal|core] [update|bindings|calls] [memory-limit-MiB=2048]\n", .{});
    std.debug.print("scenario,modules,commands,total_ms,frontend_publication_ms,lowering_ms,verification_ms,execution_ms,live_MiB,peak_MiB,checked_graph_payload_MiB,code_arenas_MiB,proof_arenas_MiB,source_arenas_MiB,diagnostic_arenas_MiB,runtime_arena_bytes,dead_frames,compiled_functions,compiled_instructions\n", .{});
    try run(init.io, count, core, scenario, limit);
}
