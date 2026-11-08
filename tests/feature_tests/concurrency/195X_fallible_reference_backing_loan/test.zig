const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "195X_fallible_reference_backing_loan" {
    const path = "tests/feature_tests/concurrency/195X_fallible_reference_backing_loan";
    try support.expectFrontendFailure(path, "pending execution");
}
