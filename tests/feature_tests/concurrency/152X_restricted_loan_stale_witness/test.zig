const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 152X_restricted_loan_stale_witness" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/152X_restricted_loan_stale_witness", "root that has ended");
}
