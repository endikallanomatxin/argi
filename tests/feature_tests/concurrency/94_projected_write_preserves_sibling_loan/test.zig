const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 94_projected_write_preserves_sibling_loan" {
    const path = "tests/feature_tests/concurrency/94_projected_write_preserves_sibling_loan";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
