const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "183X_checked_array_access_during_backing_loan" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/183X_checked_array_access_during_backing_loan", "pending execution");
}
