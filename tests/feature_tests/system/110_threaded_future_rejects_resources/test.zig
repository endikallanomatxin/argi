const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "unsupported threaded inputs are rejected before starting workers" {
    const path = "tests/feature_tests/system/110_threaded_future_rejects_resources";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
