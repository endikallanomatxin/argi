const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "ownership 403_indirect_move_cleanup_evidence" {
    const path = "tests/feature_tests/ownership/403_indirect_move_cleanup_evidence";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
