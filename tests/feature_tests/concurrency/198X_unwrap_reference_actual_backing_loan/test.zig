const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "198X_unwrap_reference_actual_backing_loan" {
    const path = "tests/feature_tests/concurrency/198X_unwrap_reference_actual_backing_loan";
    try support.expectFrontendFailure(path, "pending execution");
}
