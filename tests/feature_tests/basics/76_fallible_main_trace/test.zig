const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/76_fallible_main_trace" {
    const path = "tests/feature_tests/basics/76_fallible_main_trace";
    try support.expectSuccessfulBuild(path);
    const output = try support.outputPathFor(path);
    defer std.testing.allocator.free(output);
    const result = try support.runChild(&.{output});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try std.testing.expectEqualStrings("", result.stdout);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "error trace") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "error trace (most recent first)") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "starting application") != null);
    const location = if (@import("builtin").os.tag == .windows) "76_fallible_main_trace\\main.rg:12:" else "76_fallible_main_trace/main.rg:12:";
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, location) != null);
}
