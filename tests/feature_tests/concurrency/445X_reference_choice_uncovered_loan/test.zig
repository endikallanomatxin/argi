const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "445X_reference_choice_uncovered_loan" {
    const path = "tests/feature_tests/concurrency/445X_reference_choice_uncovered_loan";
    try support.expectFrontendFailure(path, "authenticated reference target");
}
