const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "173X_wrapped_offset_reference_wrong_loan_target" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/173X_wrapped_offset_reference_wrong_loan_target", "borrowed execution requires an authenticated reference target");
}
