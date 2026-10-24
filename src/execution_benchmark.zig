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

const Scenario = enum { update, bindings, calls, resources, definitions };
const Modules = enum { minimal, core, prelude };

fn elapsed(io: std.Io, start: i96) u64 {
    return @intCast(@max(0, std.Io.Timestamp.now(io, .boot).nanoseconds - start));
}
fn ms(value: u64) f64 {
    return @as(f64, @floatFromInt(value)) / 1_000_000;
}
fn mib(value: usize) f64 {
    return @as(f64, @floatFromInt(value)) / (1024 * 1024);
}

fn report(session: *interactive.Interactive, memory: *Memory, scenario: Scenario, modules: Modules, commands: usize, total_ns: u64) !void {
    const stats = session.runtime.stats;
    const backend_ns = stats.lowering_ns + stats.verification_ns + stats.execution_ns;
    const semantic_graph = session.compiler.semantic.relocation.graph.storageBytes();
    var code: usize = 0;
    for (session.runtime.units.items) |arena| code += arena.queryCapacity();
    var proofs: usize = 0;
    var proof = session.compiler.temporal;
    while (proof) |entry| : (proof = entry.parent) proofs += entry.arena.queryCapacity();
    var dead_frames: usize = 0;
    var dead_frame_slot_bytes: usize = 0;
    var live_frame_slot_bytes: usize = 0;
    var frame_identity_bytes: usize = 0;
    var dead_cleanup_flag_bytes: usize = 0;
    var live_cleanup_flag_bytes: usize = 0;
    if (session.runtime.context.state != .fresh) {
        const frames = session.runtime.context.storage.frames.items;
        frame_identity_bytes = frames.len * @sizeOf(@TypeOf(frames[0]));
        for (frames) |frame| {
            const bytes = frame.values.len * @sizeOf(@TypeOf(frame.values[0]));
            if (!frame.alive) {
                dead_frames += 1;
                dead_frame_slot_bytes += bytes;
                dead_cleanup_flag_bytes += frame.cleanup_flags.len;
            } else {
                live_frame_slot_bytes += bytes;
                live_cleanup_flag_bytes += frame.cleanup_flags.len;
            }
        }
    }
    var live_acquisitions: usize = 0;
    var live_acquired_bytes: usize = 0;
    var retained_acquired_bytes: usize = 0;
    if (session.runtime.context.state != .fresh) {
        for (session.runtime.context.storage.acquisitions.entries.items) |region| {
            retained_acquired_bytes += region.bytes.len + region.initialized.len;
            if (region.live) {
                live_acquisitions += 1;
                live_acquired_bytes += region.bytes.len;
            }
        }
    }
    if (scenario == .resources and live_acquisitions != commands) return error.InvalidBenchmarkAcquisitions;
    const runtime = if (session.runtime.context.state == .fresh) 0 else session.runtime.context.arena.queryCapacity();
    std.debug.print("{s},{s},{d},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d}\n", .{
        @tagName(scenario),          @tagName(modules),                          commands,
        ms(total_ns),                ms(total_ns -| backend_ns),                 ms(stats.lowering_ns),
        ms(stats.verification_ns),   ms(stats.execution_ns),                     mib(memory.live),
        mib(memory.peak),            mib(semantic_graph),                        mib(code),
        mib(proofs),                 mib(session.sources.arena.queryCapacity()), mib(session.diagnostic_arena.queryCapacity()),
        runtime,                     dead_frames,                                stats.compiled_functions,
        stats.compiled_instructions, dead_frame_slot_bytes,                      live_frame_slot_bytes,
        frame_identity_bytes,        live_acquisitions,                          live_acquired_bytes,
        retained_acquired_bytes,     dead_cleanup_flag_bytes,                    live_cleanup_flag_bytes,
    });
    // Check the actual retained value without adding a measurement submission.
    const bindings = session.compiler.semantic.resolvers.expressions.session_bindings.items;
    const frame = session.runtime.context.bindings.get(bindings[bindings.len - 1]) orelse return error.MissingBenchmarkBinding;
    const slots = try session.runtime.context.storage.slots(frame);
    if ((try slots.get(0)).integer != 42) return error.InvalidBenchmarkResult;
}

// Diagnostic-only attribution: count retained pool payload and reserved backing
// independently. Nested slices and lookup/safety arenas are not part of these
// columns and remain covered by the existing total allocation counters.
fn reportGraphPools(session: *const interactive.Interactive, commands: usize) void {
    const Graph = @import("4_semantics/global/graph.zig").GlobalSemanticGraph;
    inline for (@typeInfo(Graph).@"struct".fields) |field| {
        if (comptime switch (@typeInfo(field.type)) {
            .@"struct" => @hasField(field.type, "items") and @hasField(field.type, "capacity"),
            else => false,
        }) {
            const pool = @field(session.compiler.semantic.relocation.graph, field.name);
            const width = @sizeOf(std.meta.Elem(@TypeOf(pool.items)));
            const payload = pool.items.len * width;
            const reserved = pool.capacity * width;
            if (reserved != 0) std.debug.print("# graph_pool,{d},{s},{d},{d}\n", .{ commands, field.name, payload, reserved });
        }
    }
}

fn run(backing_allocator: std.mem.Allocator, io: std.Io, count: usize, modules: Modules, scenario: Scenario, limit: usize, graph_pools: bool) !void {
    var memory: Memory = .{ .child = backing_allocator, .limit = limit };
    const allocator = memory.allocator();
    {
        var initial_arena = std.heap.ArenaAllocator.init(allocator);
        defer initial_arena.deinit();
        const a = initial_arena.allocator();
        var session: interactive.Interactive = undefined;
        if (modules != .minimal) {
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
        var unavailable: std.Io.Writer = .failing;
        var output: @import("execution/host_output.zig").Output = .{ .writer = &unavailable, .error_writer = &unavailable };
        const host_bindings = output.bindings();
        if (modules == .prelude) {
            session.runtime.context.host_bindings = &host_bindings;
            session.initializePrelude(@embedFile("0_commands/repl_prelude.rg")) catch |err| {
                try session.diagnostics.dump();
                return err;
            };
        }
        if (scenario == .calls) try session.submitDefinitions("identity := (.value: Int32) -> (.result: Int32) { result = value }");
        try session.submitStatements("value :: Int32 = 42");
        session.runtime.profile_io = io;
        session.runtime.stats = .{};
        var total_ns: u64 = 0;
        try report(&session, &memory, scenario, modules, 0, total_ns);
        for (1..count + 1) |index| {
            const source = switch (scenario) {
                .update => try allocator.dupe(u8, "value = 42"),
                .calls => try allocator.dupe(u8, "value = identity(.value = 42)"),
                .definitions => try std.fmt.allocPrint(allocator, "function_{d} := () -> (.result: Int32) {{ result = 42 }}", .{index}),
                .bindings => try std.fmt.allocPrint(allocator, "value_{d} :: Int32 = 42", .{index}),
                .resources => try std.fmt.allocPrint(allocator, "text_{d} ::= unwrap_or_abort(.value = String(.length = 32))\nvalue_{d} :: Int32 = 42", .{ index, index }),
            };
            defer allocator.free(source);
            const start = std.Io.Timestamp.now(io, .boot).nanoseconds;
            const submitted = if (scenario == .definitions) session.submitDefinitions(source) else session.submitStatements(source);
            submitted catch |err| {
                std.debug.print("Stopped after {d} commands: {s}; retained {d:.3} MiB, peak {d:.3} MiB\n", .{ index - 1, @errorName(err), mib(memory.live), mib(memory.peak) });
                try session.diagnostics.dump();
                return err;
            };
            total_ns += elapsed(io, start);
            if (index == 10 or index == 100 or index == 1000 or index == count) try report(&session, &memory, scenario, modules, index, total_ns);
        }
        if (scenario == .definitions) {
            const call = try std.fmt.allocPrint(allocator, "function_{d}()", .{count});
            defer allocator.free(call);
            const result = (try session.submitInput(call)) orelse return error.MissingBenchmarkResult;
            if (result.value != .runtime or result.value.runtime != .integer or result.value.runtime.integer != 42) return error.InvalidBenchmarkResult;
        }
        if (graph_pools) reportGraphPools(&session, count);
        // Snapshot before cleanup; include neither reset nor teardown in timings.
        try session.close();
    }
    if (memory.live != 0) {
        std.debug.print("Benchmark teardown retained {d} requested bytes\n", .{memory.live});
        return error.BenchmarkMemoryLeak;
    }
}

// Isolate verifier allocations from graph construction and session retention.
// Diamonds retain one join per block; linear code has the same slot count.
fn benchmarkVerifier(io: std.Io) !void {
    const b = @import("5_codegen/bytecode/bytecode.zig");
    const g = @import("4_semantics/global/graph.zig");
    const verify = @import("5_codegen/bytecode/verify.zig").verify;
    const a = std.heap.page_allocator;
    var graph: g.GlobalSemanticGraph = .{};
    defer graph.deinit(a);
    try graph.types.append(a, .{ .builtin = .Bool });
    const source = @import("4_semantics/primitives/schema.zig").SourceRef{ .file_index = 0, .offset = 0 };
    std.debug.print("shape,slots,instructions,verification_ms,requested_bytes,peak_bytes,retained_bytes\n", .{});
    for ([_]usize{ 10, 100, 1000 }) |count| {
        const slots = try a.alloc(b.Type, count);
        defer a.free(slots);
        @memset(slots, @enumFromInt(0));
        for ([_]bool{ false, true }) |diamonds| {
            const code = try a.alloc(b.Instruction, (if (diamonds) count * 3 else count) + 1);
            defer a.free(code);
            if (diamonds) {
                for (0..count) |index| {
                    const pc: u32 = @intCast(index * 3);
                    code[pc] = .{ .source = source, .op = .{ .branch = .{ .condition = 0, .yes = pc + 1, .no = pc + 2 } } };
                    code[pc + 1] = .{ .source = source, .op = .{ .jump = pc + 3 } };
                    code[pc + 2] = .{ .source = source, .op = .{ .jump = pc + 3 } };
                }
            } else {
                for (code[0..count], 0..) |*instruction, index| {
                    instruction.* = .{ .source = source, .op = .{ .constant = .{ .dst = @intCast(index), .value = .{ .boolean = true } } } };
                }
            }
            code[code.len - 1] = .{ .source = source, .op = .{ .ret = &.{0} } };
            const function = b.Function{ .slots = slots, .inputs = &.{0}, .outputs = &.{0}, .code = code };
            var memory: Memory = .{ .limit = 128 * 1024 * 1024 };
            var requested: u64 = 0;
            var allocations = @import("1_base/profile.zig").AllocationCounter{ .child = memory.allocator(), .requested_bytes = &requested };
            const start = std.Io.Timestamp.now(io, .boot).nanoseconds;
            try verify(allocations.allocator(), .{ .graph = &graph, .functions = &.{}, .expression = &function });
            const duration = elapsed(io, start);
            std.debug.print("{s},{d},{d},{d:.3},{d},{d},{d}\n", .{ if (diamonds) "diamonds" else "linear", count, code.len, ms(duration), requested, memory.peak, memory.live });
            if (memory.live != 0) return error.VerifierRetainedMemory;
        }
    }
}

pub fn main(init: std.process.Init) !void {
    const raw_args = try init.minimal.args.toSlice(init.arena.allocator());
    const graph_pools = raw_args.len > 1 and std.mem.eql(u8, raw_args[raw_args.len - 1], "--graph-pools");
    const args = raw_args[0 .. raw_args.len - @intFromBool(graph_pools)];
    if (args.len == 2 and std.mem.eql(u8, args[1], "--verifier")) return benchmarkVerifier(init.io);
    if (args.len > 5) return error.InvalidArguments;
    const count = if (args.len >= 2) try std.fmt.parseInt(usize, args[1], 10) else 1000;
    if (count == 0 or count == std.math.maxInt(usize)) return error.InvalidArguments;
    const modules = if (args.len >= 3) std.meta.stringToEnum(Modules, args[2]) orelse return error.InvalidArguments else .minimal;
    const scenario = if (args.len >= 4) std.meta.stringToEnum(Scenario, args[3]) orelse return error.InvalidArguments else .update;
    if (scenario == .resources and modules != .prelude) return error.ResourcesRequirePrelude;
    const memory_mib = if (args.len >= 5) try std.fmt.parseInt(usize, args[4], 10) else 2048;
    const limit = try std.math.mul(usize, memory_mib, 1024 * 1024);
    std.debug.print("# [commands=1000] [minimal|core|prelude] [update|bindings|calls|resources|definitions] [memory-limit-MiB=2048] [--graph-pools]\n", .{});
    std.debug.print("scenario,modules,commands,total_ms,frontend_publication_ms,lowering_ms,verification_ms,execution_ms,live_MiB,peak_MiB,semantic_graph_payload_MiB,code_arenas_MiB,proof_arenas_MiB,source_arenas_MiB,diagnostic_arenas_MiB,runtime_arena_bytes,dead_frames,compiled_functions,compiled_instructions,dead_frame_slot_bytes,live_frame_slot_bytes,frame_identity_bytes,live_acquisitions,live_acquired_bytes,retained_acquired_bytes,dead_cleanup_flag_bytes,live_cleanup_flag_bytes\n", .{});
    try run(init.gpa, init.io, count, modules, scenario, limit, graph_pools);
}
