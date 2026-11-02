const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/275_comptime_system_entry" {
    const built = try support.buildResult("tests/feature_tests/execution/275_comptime_system_entry");
    defer std.testing.allocator.free(built.stdout);
    defer std.testing.allocator.free(built.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, built.term);
    try std.testing.expect(std.mem.count(u8, built.stdout, "compile-time host") == 1);
    try support.runExpect("tests/feature_tests/execution/275_comptime_system_entry", 42);
    try support.vmExpect("tests/feature_tests/execution/275_comptime_system_entry", 42, null);
}
