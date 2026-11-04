const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 15X_wrapper_retains_loan" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/15X_wrapper_retains_loan", "pending execution");
}
