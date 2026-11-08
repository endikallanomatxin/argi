const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "190_retyped_wrapper_preserves_backing_observation" {
    const path = "tests/feature_tests/concurrency/190_retyped_wrapper_preserves_backing_observation";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
