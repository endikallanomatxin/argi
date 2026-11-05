const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 106_helper_completion_allows_disjoint_loan" {
    const path = "tests/feature_tests/concurrency/106_helper_completion_allows_disjoint_loan";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
