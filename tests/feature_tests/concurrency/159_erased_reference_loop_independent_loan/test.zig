const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "159_erased_reference_loop_independent_loan" {
    const path = "tests/feature_tests/concurrency/159_erased_reference_loop_independent_loan";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
