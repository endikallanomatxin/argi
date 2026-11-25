const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "447X_rhs_starts_overlapping_loan" {
    const path = "tests/feature_tests/concurrency/447X_rhs_starts_overlapping_loan";
    try support.expectFrontendFailure(path, "write access overlaps an active write loan");
}
