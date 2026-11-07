const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "158X_erased_reference_retarget_after_loan_storage" {
    const path = "tests/feature_tests/concurrency/158X_erased_reference_retarget_after_loan_storage";
    try support.expectFrontendFailure(path, "reference access has unknown memory effects");
}
