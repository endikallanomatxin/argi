const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "system executor runs a typed future" {
    const path = "tests/feature_tests/system/117_future_argument_defaults";
    try support.expectSuccessfulBuild(path);
    try support.runExpect(path, 0);
}
