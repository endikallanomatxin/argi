const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "156_erased_reference_before_independent_loan" {
    const path = "tests/feature_tests/concurrency/156_erased_reference_before_independent_loan";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
