const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/61_process_errors" {
    const path = "tests/feature_tests/system/61_process_errors";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
