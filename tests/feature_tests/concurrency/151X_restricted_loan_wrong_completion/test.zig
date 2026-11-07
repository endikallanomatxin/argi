const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 151X_restricted_loan_wrong_completion" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/151X_restricted_loan_wrong_completion", "cannot end storage borrowed by a pending execution");
}
