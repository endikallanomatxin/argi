const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "170X_reinterpreted_reference_wrong_loan_extent" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/170X_reinterpreted_reference_wrong_loan_extent", "borrowed execution requires an authenticated reference target");
}
