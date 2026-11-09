const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "197_unwrap_preserves_reference_observation" {
    const path = "tests/feature_tests/concurrency/197_unwrap_preserves_reference_observation";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
