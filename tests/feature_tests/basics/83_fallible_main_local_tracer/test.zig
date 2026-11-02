const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/83_fallible_main_local_tracer" {
    const path = "tests/feature_tests/basics/83_fallible_main_local_tracer";
    try support.expectSuccessfulBuild(path);
    const output = try support.outputPathFor(path);
    defer std.testing.allocator.free(output);
    const result = try support.runChild(&.{output});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try std.testing.expectEqualStrings("", result.stdout);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "error trace (most recent first)") != null);
    const location = if (@import("builtin").os.tag == .windows) "83_fallible_main_local_tracer\\main.rg:6:" else "83_fallible_main_local_tracer/main.rg:6:";
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, location) != null);
}
