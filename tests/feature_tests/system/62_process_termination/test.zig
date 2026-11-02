const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/62_process_termination" {
    const path = "tests/feature_tests/system/62_process_termination";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
