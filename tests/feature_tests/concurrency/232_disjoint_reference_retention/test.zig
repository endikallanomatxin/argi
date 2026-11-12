const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "232_disjoint_reference_retention" {
    const path = "tests/feature_tests/concurrency/232_disjoint_reference_retention";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
