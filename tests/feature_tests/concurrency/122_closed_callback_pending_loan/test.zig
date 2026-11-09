const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 122_closed_callback_pending_loan" {
    try support.expectSuccessfulBuild("tests/feature_tests/concurrency/122_closed_callback_pending_loan");
    try support.runExpect("tests/feature_tests/concurrency/122_closed_callback_pending_loan", 0);
}
