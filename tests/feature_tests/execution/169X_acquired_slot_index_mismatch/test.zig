const std = @import("std");
const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/169X_acquired_slot_index_mismatch" {
    try support.expectSuccessfulBuild("tests/feature_tests/execution/169X_acquired_slot_index_mismatch");
    try support.runExpectFailure("tests/feature_tests/execution/169X_acquired_slot_index_mismatch");
    const result = try support.runArgiCommand(&.{ "run", "--vm", "tests/feature_tests/execution/169X_acquired_slot_index_mismatch" });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 1 }, result.term);
    try support.expectDiagnostic("tests/feature_tests/execution/169X_acquired_slot_index_mismatch", result.stderr, "ExecutionAborted");
    try support.expectDiagnostic("tests/feature_tests/execution/169X_acquired_slot_index_mismatch", result.stderr, "allocation_slots.rg:");
}
