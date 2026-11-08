const std = @import("std");
const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "typed CLI errors report through tracer and preserve cleanup" {
    const path = "tests/feature_tests/system/90_cli_parse_trace";
    try support.expectSuccessfulBuild(path);
    const binary = try support.outputPathFor(path);
    defer std.testing.allocator.free(binary);
    for ([_]struct { args: []const []const u8, code: u8, message: []const u8, argument: []const u8, value: []const u8 }{
        .{ .args = &.{ "run", "--jobs", "8" }, .code = 0, .message = "", .argument = "", .value = "" },
        .{ .args = &.{"--help"}, .code = 0, .message = "", .argument = "", .value = "" },
        .{ .args = &.{ "run", "--jobs", "256" }, .code = 2, .message = "invalid argument value", .argument = "jobs", .value = "256" },
        .{ .args = &.{ "run", "--unknown" }, .code = 2, .message = "unknown option", .argument = "unknown", .value = "" },
        .{ .args = &.{ "run", "--jobs" }, .code = 2, .message = "missing option value", .argument = "jobs", .value = "" },
        .{ .args = &.{"run"}, .code = 2, .message = "missing required argument", .argument = "jobs", .value = "" },
    }) |case| {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit(std.testing.allocator);
        try argv.append(std.testing.allocator, binary);
        try argv.appendSlice(std.testing.allocator, case.args);
        const result = try support.runChild(argv.items);
        defer std.testing.allocator.free(result.stdout);
        defer std.testing.allocator.free(result.stderr);
        try std.testing.expectEqual(std.process.Child.Term{ .exited = case.code }, result.term);
        try std.testing.expect(std.mem.endsWith(u8, result.stdout, "cleanup\n"));
        if (case.code == 0) {
            try std.testing.expectEqualStrings("", result.stderr);
        } else {
            for ([_][]const u8{ "invalid command-line arguments", case.message, case.argument, case.value }) |text|
                try std.testing.expect(std.mem.indexOf(u8, result.stderr, text) != null);
        }
    }
}
