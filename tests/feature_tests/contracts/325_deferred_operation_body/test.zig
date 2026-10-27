const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/325_deferred_operation_body" {
    try support.expectSuccessfulBuild("tests/feature_tests/contracts/325_deferred_operation_body");
    const result = try support.runChild(&.{ support.argi_bin, "check", "tests/feature_tests/contracts/325_deferred_operation_body" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try std.testing.expect(result.term == .exited and result.term.exited != 0);
    try std.testing.expect(std.mem.indexOf(u8, result.stderr, "cannot materialize function body") != null);
}
