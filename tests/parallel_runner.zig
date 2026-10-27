//! Process-isolated program-test shards. Each process runs its cases serially,
//! because std.testing's allocator and I/O instance are global state.
const std = @import("std");
const builtin = @import("builtin");
const options = @import("program_test_options");
const sharding = @import("program_test_sharding");
const suite = @import("program_tests");

pub const std_options: std.Options = .{ .logFn = log };
var log_errors: usize = 0;

pub fn main(init: std.process.Init.Minimal) !void {
    const allocator = std.heap.page_allocator;
    const args = try init.args.toSlice(allocator);
    defer allocator.free(args);
    if (args.len < 2 or args.len > 3) return error.ExpectedShardArgument;
    const runner_io = std.Io.Threaded.global_single_threaded.io();
    const progress_file: ?std.Io.File = if (args.len == 3) file: {
        try std.Io.Dir.cwd().createDirPath(runner_io, std.fs.path.dirname(args[2]).?);
        break :file try std.Io.Dir.cwd().createFile(runner_io, args[2], .{});
    } else null;
    defer if (progress_file) |file| file.close(runner_io);
    var progress_buffer: [4096]u8 = undefined;
    var progress_writer: ?std.Io.File.Writer = if (progress_file) |file| file.writerStreaming(runner_io, &progress_buffer) else null;
    const root_node = std.Progress.start(runner_io, .{ .root_name = "Program tests" });
    defer root_node.end();

    var namespaces: std.StringHashMap(usize) = .init(allocator);
    defer namespaces.deinit();
    try namespaces.put(suite.central_prefix, suite.groups.len);
    for (suite.groups, 0..) |group, index| {
        const entry = try namespaces.getOrPut(group.prefix);
        if (entry.found_existing) return error.DuplicateTestNamespace;
        entry.value_ptr.* = index;
    }
    const assignments = try allocator.alloc(usize, builtin.test_functions.len);
    defer allocator.free(assignments);
    const covered = try allocator.alloc(bool, suite.groups.len);
    defer allocator.free(covered);
    @memset(covered, false);
    for (builtin.test_functions, assignments) |test_fn, *assignment| {
        assignment.* = sharding.groupIndex(&namespaces, test_fn.name) orelse {
            std.debug.print("test has no discovered group: {s}\n", .{test_fn.name});
            return error.UnknownTestNamespace;
        };
        if (assignment.* < covered.len) covered[assignment.*] = true;
    }
    if (!options.filtered) for (covered, suite.groups) |present, group| {
        if (!present) {
            std.debug.print("discovered file declares no tests: {s}/test.zig\n", .{group.fixture});
            return error.EmptyFixtureTestFile;
        }
    };

    var passed: usize = 0;
    var skipped: usize = 0;
    var failed: usize = 0;
    var leaks: usize = 0;
    for (builtin.test_functions, assignments) |test_fn, assignment| {
        const group: ?suite.Group = if (assignment < suite.groups.len) suite.groups[assignment] else null;
        const fixture = if (group) |g| g.fixture else null;
        const exclusive = if (group) |g| g.isolation == .exclusive else true;
        if (!try sharding.selected(fixture, exclusive, args[1], options.workers)) continue;
        const started = std.Io.Timestamp.now(runner_io, .boot).nanoseconds;
        var outcome: []const u8 = "passed";
        std.testing.allocator_instance = .{};
        std.testing.io_instance = .init(std.testing.allocator, .{
            .argv0 = .init(init.args),
            .environ = init.environ,
        });
        std.testing.environ = init.environ;
        std.testing.log_level = .warn;
        const test_node = root_node.start(test_fn.name, 0);
        if (options.progress) {
            if (progress_writer) |*writer| {
                try writer.interface.print("[programs {s}] {s}...\n", .{ args[1], test_fn.name });
                try writer.interface.flush();
            }
        }
        if (test_fn.func()) |_| {
            passed += 1;
        } else |err| switch (err) {
            error.SkipZigTest => {
                skipped += 1;
                outcome = "skipped";
            },
            else => {
                failed += 1;
                outcome = "failed";
                std.debug.print("[programs {s}] FAIL {s}: {s}\n", .{ args[1], test_fn.name, @errorName(err) });
                if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
            },
        }
        test_node.end();
        std.testing.io_instance.deinit();
        const leaked = std.testing.allocator_instance.deinit() == .leak;
        if (leaked) leaks += 1;
        if (progress_writer) |*writer| {
            const elapsed = std.Io.Timestamp.now(runner_io, .boot).nanoseconds - started;
            try writer.interface.print("case\t{s}\t{s}\t{d} ns\t{s}\tleak={}\n", .{ if (exclusive) "exclusive" else "fixture", outcome, elapsed, test_fn.name, leaked });
            try writer.interface.flush();
        }
    }
    var stdout_buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(runner_io, &stdout_buffer);
    const format = "[programs {s}] {d} passed; {d} skipped; {d} failed; {d} leaks; {d} error logs\n";
    const totals = .{ args[1], passed, skipped, failed, leaks, log_errors };
    try stdout.interface.print(format, totals);
    try stdout.interface.flush();
    if (progress_writer) |*writer| {
        try writer.interface.print(format, totals);
        try writer.interface.flush();
    }
    if (failed != 0 or leaks != 0 or log_errors != 0) std.process.exit(1);
}

fn log(comptime level: std.log.Level, comptime scope: @EnumLiteral(), comptime format: []const u8, args: anytype) void {
    if (level == .err) log_errors += 1;
    if (@intFromEnum(level) <= @intFromEnum(std.testing.log_level))
        std.debug.print("[" ++ @tagName(scope) ++ "] " ++ @tagName(level) ++ ": " ++ format ++ "\n", args);
}
