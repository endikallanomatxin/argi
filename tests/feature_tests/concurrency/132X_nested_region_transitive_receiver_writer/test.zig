const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency/132X_nested_region_transitive_receiver_writer" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/132X_nested_region_transitive_receiver_writer", "pending execution");
}
