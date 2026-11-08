const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "169X_offset_reference_wrong_loan_target" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/169X_offset_reference_wrong_loan_target", "borrowed execution requires an authenticated reference target");
}
