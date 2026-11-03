const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "threaded future owns stable task storage across moves" {
    const path = "tests/feature_tests/system/108_threaded_future";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
