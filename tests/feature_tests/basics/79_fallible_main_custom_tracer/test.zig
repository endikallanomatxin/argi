const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/79_fallible_main_custom_tracer" {
    const path = "tests/feature_tests/basics/79_fallible_main_custom_tracer";
    try support.expectSuccessfulBuild(path);
    const output = try support.outputPathFor(path);
    defer std.testing.allocator.free(output);
    const result = try support.runChild(&.{output});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try std.testing.expectEqualStrings("custom trace\n", result.stderr);
}
