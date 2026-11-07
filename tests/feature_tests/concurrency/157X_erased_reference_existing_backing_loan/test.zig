const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "157X_erased_reference_existing_backing_loan" {
    const path = "tests/feature_tests/concurrency/157X_erased_reference_existing_backing_loan";
    try support.expectFrontendFailure(path, "reference access has unknown memory effects");
}
