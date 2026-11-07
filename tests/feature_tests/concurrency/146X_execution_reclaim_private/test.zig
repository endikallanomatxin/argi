const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 146X_execution_reclaim_private" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/146X_execution_reclaim_private", "no function");
}
