const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 23X_factory_other_execution_pending" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/23X_factory_other_execution_pending", "pending execution");
}
