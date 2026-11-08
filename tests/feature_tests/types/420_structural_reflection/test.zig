const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "feature_tests/types/420_structural_reflection" {
    const path = "tests/feature_tests/types/420_structural_reflection";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
