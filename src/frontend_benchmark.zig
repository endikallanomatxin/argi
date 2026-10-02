const std = @import("std");
const sf = @import("1_base/source_files.zig");
const diag = @import("1_base/diagnostic.zig");
const frontend = @import("0_commands/frontend_pipeline.zig");
const ModuleCache = frontend.cache.ModuleCache;

const Sample = struct {
    total: u64 = 0,
    tokenizing: u64 = 0,
    syntaxing: u64 = 0,
    module: u64 = 0,
    linked: u64 = 0,
    global: u64 = 0,
    safety: u64 = 0,
    hits: usize = 0,
    misses: usize = 0,
};

fn measure(io: std.Io, files: []const sf.SourceFile, session: ?*ModuleCache, edit: ?usize, revision: usize) !Sample {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const inputs = try allocator.dupe(sf.SourceFile, files);
    if (edit) |index| inputs[index].code = try std.fmt.allocPrint(allocator, "{s}\n-- benchmark revision {d}\n", .{ inputs[index].code, revision });
    var diagnostics = diag.Diagnostics.init(&allocator, inputs);
    defer diagnostics.deinit();
    var pipeline = frontend.FrontendPipeline.init(allocator, io, &diagnostics, .{
        .collect_stats = true,
        .module_cache = session,
    });
    defer pipeline.deinit();
    const start = std.Io.Timestamp.now(io, .boot).nanoseconds;
    _ = pipeline.semantizeGlobalFiles(inputs) catch |err| {
        try diagnostics.dump();
        return err;
    };
    return .{
        .total = @intCast(std.Io.Timestamp.now(io, .boot).nanoseconds - start),
        .tokenizing = pipeline.tokenizing_ns,
        .syntaxing = pipeline.syntaxing_ns,
        .module = pipeline.module_semantizing_ns,
        .linked = pipeline.linked_module_ns,
        .global = pipeline.global_semantic_ns,
        .safety = pipeline.safety_ns,
        .hits = pipeline.module_cache_hits,
        .misses = pipeline.module_cache_misses,
    };
}

fn milliseconds(ns: u64, iterations: usize) f64 {
    return @as(f64, @floatFromInt(ns)) / @as(f64, @floatFromInt(iterations)) / 1_000_000;
}

fn benchmark(io: std.Io, files: []const sf.SourceFile, name: []const u8, edit: ?usize, iterations: usize, reuse: bool) !void {
    var session = ModuleCache.init(std.heap.page_allocator, .{});
    defer session.deinit();
    const cache = if (reuse) &session else null;
    // Prime both paths before timing to avoid mixing initial process/LLVM setup
    // with steady-state rebuilds. A cold session is reported separately.
    _ = try measure(io, files, cache, null, 0);
    var totals: Sample = .{};
    for (0..iterations) |index| {
        const sample = try measure(io, files, cache, edit, index);
        inline for (std.meta.fields(Sample)) |field| @field(totals, field.name) += @field(sample, field.name);
    }
    std.debug.print("{s},{s},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d:.3},{d},{d},{d:.2}\n", .{
        name,                                       if (reuse) @as([]const u8, "reuse") else "clean",
        milliseconds(totals.total, iterations),     milliseconds(totals.tokenizing, iterations),
        milliseconds(totals.syntaxing, iterations), milliseconds(totals.module, iterations),
        milliseconds(totals.linked, iterations),    milliseconds(totals.global, iterations),
        milliseconds(totals.safety, iterations),    totals.hits / iterations,
        totals.misses / iterations,                 @as(f64, @floatFromInt(session.retained_bytes)) / (1024 * 1024),
    });
}

pub fn main(init: std.process.Init) !void {
    var allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 2 or args.len > 3) {
        std.debug.print("Usage: zig build benchmark-frontend -- <module-directory> [iterations]\n", .{});
        return error.InvalidArguments;
    }
    const iterations = if (args.len == 3) try std.fmt.parseInt(usize, args[2], 10) else 10;
    if (iterations == 0) return error.InvalidArguments;
    const dir = try std.fs.path.resolve(allocator, &.{args[1]});
    const files = try sf.collectModule(&allocator, init.io, "core", dir);
    var local: ?usize = null;
    var imported: ?usize = null;
    var core: ?usize = null;
    for (files.items, 0..) |file, index| {
        if (file.origin == .bundled_core) {
            if (core == null) core = index;
        } else if (std.mem.eql(u8, std.fs.path.dirname(file.path) orelse ".", dir)) {
            if (local == null) local = index;
        } else if (imported == null) imported = index;
    }
    var cold = ModuleCache.init(std.heap.page_allocator, .{});
    defer cold.deinit();
    const sample = try measure(init.io, files.items, &cold, null, 0);
    std.debug.print("Cold session: {d:.3} ms, {d} modules, {d:.2} MiB retained\n", .{
        milliseconds(sample.total, 1),                                cold.entries.items.len,
        @as(f64, @floatFromInt(cold.retained_bytes)) / (1024 * 1024),
    });
    std.debug.print("scenario,mode,frontend_ms,tokenizing_ms,syntaxing_ms,module_ms,linked_ms,global_ms,safety_ms,hits,misses,retained_MiB\n", .{});
    for ([_][]const u8{ "unchanged", "local_edit", "import_edit", "core_edit" }, [_]?usize{ null, local, imported, core }, 0..) |name, edit, index| {
        if (index != 0 and edit == null) continue;
        try benchmark(init.io, files.items, name, edit, iterations, false);
        try benchmark(init.io, files.items, name, edit, iterations, true);
    }
}
