const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "182_checked_array_access_during_independent_loan" {
    try support.expectSuccessfulBuild("tests/feature_tests/concurrency/182_checked_array_access_during_independent_loan");
    try support.runExpect("tests/feature_tests/concurrency/182_checked_array_access_during_independent_loan", 0);
}
