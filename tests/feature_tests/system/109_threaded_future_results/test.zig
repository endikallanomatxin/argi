const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "threaded futures preserve complete output shapes and single extraction" {
    const path = "tests/feature_tests/system/109_threaded_future_results";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
