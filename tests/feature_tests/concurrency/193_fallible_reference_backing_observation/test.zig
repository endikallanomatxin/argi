const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "193_fallible_reference_backing_observation" {
    const path = "tests/feature_tests/concurrency/193_fallible_reference_backing_observation";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
