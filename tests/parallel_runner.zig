//! Process-isolated tests with explicit fixture discovery and isolation metadata.
const std = @import("std");
const builtin = @import("builtin");
const options = @import("program_test_options");
const sharding = @import("test_harness").sharding;
const inventory = @import("test_harness").catalog;
const executor = @import("test_harness").executor;
const support = @import("test_harness").support;

pub const std_options: std.Options = .{ .logFn = log };
var log_errors: usize = 0;

pub fn main(init: std.process.Init.Minimal) !void {
    const allocator = std.heap.page_allocator;
    const args = try init.args.toSlice(allocator);
    defer allocator.free(args);
    if (args.len != 3) return error.ExpectedShardAndLogPath;
    const io = std.Io.Threaded.global_single_threaded.io();
    var catalog: inventory.Catalog = undefined;
    try catalog.init(allocator, io, support.compilerRoot());
    defer catalog.deinit();
    var custom: std.StringHashMap(*const fn () anyerror!void) = .init(allocator);
    defer custom.deinit();
    for (builtin.test_functions) |test_fn| {
        const name = catalog.customName(test_fn.name) orelse {
            std.debug.print("custom test has no explicit metadata: {s}\n", .{test_fn.name});
            return error.MissingCustomTestMetadata;
        };
        if (custom.contains(name)) return error.DuplicateCustomTest;
        try custom.put(name, test_fn.func);
    }
    for (catalog.entries.items) |entry| {
        if (entry.custom and inventory.matchesFilters(entry.name, options.filters) and !custom.contains(entry.name)) {
            std.debug.print("custom metadata names no compiled test: {s}\n", .{entry.name});
            return error.StaleCustomTestMetadata;
        }
    }
    try std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(args[2]).?);
    const progress_file = try std.Io.Dir.cwd().createFile(io, args[2], .{});
    defer progress_file.close(io);
    var progress_buffer: [4096]u8 = undefined;
    var progress = progress_file.writerStreaming(io, &progress_buffer);
    const timing_path = try std.fmt.allocPrint(allocator, "{s}.jsonl", .{args[2]});
    defer allocator.free(timing_path);
    const timing_file = try std.Io.Dir.cwd().createFile(io, timing_path, .{});
    defer timing_file.close(io);
    var timing_buffer: [4096]u8 = undefined;
    var timings = timing_file.writerStreaming(io, &timing_buffer);
    const root_node = std.Progress.start(io, .{ .root_name = "Program tests" });
    defer root_node.end();
    var passed: usize = 0;
    var skipped: usize = 0;
    var failed: usize = 0;
    var leaks: usize = 0;
    for (catalog.entries.items) |entry| {
        if (!inventory.matchesFilters(entry.name, options.filters) or !try sharding.selected(entry, args[1], options.workers)) continue;
        const started = std.Io.Timestamp.now(io, .boot).nanoseconds;
        std.testing.allocator_instance = .{};
        std.testing.io_instance = .init(std.testing.allocator, .{ .argv0 = .init(init.args), .environ = init.environ });
        std.testing.environ = init.environ;
        std.testing.log_level = .warn;
        const test_node = root_node.start(entry.name, 0);
        if (options.progress) {
            try progress.interface.print("[programs {s}] {s}...\n", .{ args[1], entry.name });
            try progress.interface.flush();
        }
        const result = if (entry.custom) custom.get(entry.name).?() else executor.execute(entry.fixture.?, entry.steps);
        var status: enum { passed, skipped, failed } = .passed;
        if (result) |_| {
            passed += 1;
        } else |err| switch (err) {
            error.SkipZigTest => {
                skipped += 1;
                status = .skipped;
            },
            else => {
                failed += 1;
                status = .failed;
                std.debug.print("[programs {s}] FAIL {s}: {s}\n", .{ args[1], entry.name, @errorName(err) });
                if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
            },
        }
        test_node.end();
        std.testing.io_instance.deinit();
        const leaked = std.testing.allocator_instance.deinit() == .leak;
        if (leaked) leaks += 1;
        const elapsed: u64 = @intCast(@max(0, std.Io.Timestamp.now(io, .boot).nanoseconds - started));
        try std.json.Stringify.value(.{
            .name = entry.name,
            .fixture = entry.fixture,
            .origin = if (entry.custom) "custom" else "descriptor",
            .isolation = @tagName(entry.isolation),
            .shard = args[1],
            .duration_ns = elapsed,
            .result = @tagName(status),
            .leaked = leaked,
        }, .{}, &timings.interface);
        try timings.interface.writeByte('\n');
        try timings.interface.flush();
    }
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &stdout_buffer);
    const format = "[programs {s}] {d} passed; {d} skipped; {d} failed; {d} leaks; {d} error logs\n";
    const totals = .{ args[1], passed, skipped, failed, leaks, log_errors };
    try stdout.interface.print(format, totals);
    try stdout.interface.flush();
    try progress.interface.print(format, totals);
    try progress.interface.flush();
    if (failed != 0 or leaks != 0 or log_errors != 0) std.process.exit(1);
}

fn log(comptime level: std.log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype) void {
    if (level == .err) log_errors += 1;
    if (@intFromEnum(level) <= @intFromEnum(std.testing.log_level))
        std.debug.print("[" ++ @tagName(scope) ++ "] " ++ format ++ "\n", args);
}
