const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "201_snapshot_reference_retargeted_independent" {
    const path = "tests/feature_tests/concurrency/201_snapshot_reference_retargeted_independent";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
