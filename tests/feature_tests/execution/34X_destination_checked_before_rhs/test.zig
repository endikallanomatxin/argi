const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/34X_destination_checked_before_rhs" {
    const fixture = "tests/feature_tests/execution/34X_destination_checked_before_rhs";
    try support.expectSuccessfulBuild(fixture);
    const path = try support.outputPathFor(fixture);
    defer std.testing.allocator.free(path);
    const result = try support.runChild(&.{path});
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try std.testing.expect(result.term != .exited or result.term.exited != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "runtime error: array index is out of bounds") != null);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "explicit abort") == null);
    try support.vmExpect("tests/feature_tests/execution/34X_destination_checked_before_rhs", 1, "ExecutionIndexOutOfBounds");
}
