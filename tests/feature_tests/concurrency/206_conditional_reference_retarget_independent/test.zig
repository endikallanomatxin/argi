const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "206_conditional_reference_retarget_independent" {
    const path = "tests/feature_tests/concurrency/206_conditional_reference_retarget_independent";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
