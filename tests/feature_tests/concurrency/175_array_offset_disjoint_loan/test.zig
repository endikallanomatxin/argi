const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "175_array_offset_disjoint_loan" {
    try support.expectSuccessfulBuild("tests/feature_tests/concurrency/175_array_offset_disjoint_loan");
    try support.runExpect("tests/feature_tests/concurrency/175_array_offset_disjoint_loan", 0);
}
