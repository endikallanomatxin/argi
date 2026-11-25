const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "444X_reference_choice_loan_conflict" {
    const path = "tests/feature_tests/concurrency/444X_reference_choice_loan_conflict";
    try support.expectFrontendFailure(path, "pending execution");
}
