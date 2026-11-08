const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "172X_erased_reference_widened_loan_extent" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/172X_erased_reference_widened_loan_extent", "borrowed execution requires an authenticated reference target");
}
