//! Process-isolated program-test shards. Each process runs its cases serially,
//! because std.testing's allocator and I/O instance are global state.
const std = @import("std");
const builtin = @import("builtin");
const options = @import("program_test_options");
const sharding = @import("program_test_sharding");

pub const std_options: std.Options = .{ .logFn = log };
var log_errors: usize = 0;

pub fn main(init: std.process.Init.Minimal) !void {
    const allocator = std.heap.page_allocator;
    const args = try init.args.toSlice(allocator);
    defer allocator.free(args);
    if (args.len < 2 or args.len > 3) return error.ExpectedShardArgument;
    const serial = std.mem.eql(u8, args[1], "serial");
    const worker = if (serial) 0 else try std.fmt.parseUnsigned(u32, args[1], 10);
    if (!serial and worker >= options.workers) return error.InvalidShard;

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

    var tree = try std.zig.Ast.parse(allocator, @embedFile("test.zig"), .zig);
    defer tree.deinit(allocator);
    var keys: std.StringHashMap(?[]const u8) = .init(allocator);
    defer keys.deinit();
    for (tree.rootDecls()) |node| {
        if (tree.nodeTag(node) != .test_decl) continue;
        const name_token = tree.nodeData(node).opt_token_and_node[0].unwrap() orelse continue;
        const literal = tree.tokenSlice(name_token);
        try keys.put(literal[1 .. literal.len - 1], sharding.fixtureKey(&tree, node));
    }

    var passed: usize = 0;
    var skipped: usize = 0;
    var failed: usize = 0;
    var leaks: usize = 0;
    for (builtin.test_functions) |test_fn| {
        // Root test names are prefixed by their Zig module name.
        var source_name = test_fn.name;
        while (!keys.contains(source_name)) {
            const separator = std.mem.indexOfScalar(u8, source_name, '.') orelse break;
            source_name = source_name[separator + 1 ..];
        }
        const key = if (keys.get(source_name)) |entry| entry else null;
        if (key) |fixture| {
            if (serial or sharding.workerFor(fixture, options.workers) != worker) continue;
        } else if (!serial) continue;

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
            error.SkipZigTest => skipped += 1,
            else => {
                failed += 1;
                std.debug.print("[programs {s}] FAIL {s}: {s}\n", .{ args[1], test_fn.name, @errorName(err) });
                if (@errorReturnTrace()) |trace| std.debug.dumpErrorReturnTrace(trace);
            },
        }
        test_node.end();
        std.testing.io_instance.deinit();
        if (std.testing.allocator_instance.deinit() == .leak) leaks += 1;
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
