const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/70_process_argument_lifetime" {
    const path = "tests/feature_tests/system/70_process_argument_lifetime";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
