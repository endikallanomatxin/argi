const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "448_rhs_completes_overlapping_loan" {
    const path = "tests/feature_tests/concurrency/448_rhs_completes_overlapping_loan";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
