const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "181_checked_array_projection_preserves_observation" {
    const path = "tests/feature_tests/concurrency/181_checked_array_projection_preserves_observation";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
