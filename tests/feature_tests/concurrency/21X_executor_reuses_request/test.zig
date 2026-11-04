const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 21X_executor_reuses_request" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/21X_executor_reuses_request", "moved");
}
