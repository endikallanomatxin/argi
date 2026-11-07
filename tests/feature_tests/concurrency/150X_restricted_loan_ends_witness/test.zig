const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 150X_restricted_loan_ends_witness" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/150X_restricted_loan_ends_witness", "cannot end storage borrowed by a pending execution");
}
