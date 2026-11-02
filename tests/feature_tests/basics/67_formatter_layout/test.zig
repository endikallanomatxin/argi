const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/67_formatter_layout" {
    const path = "tests/feature_tests/basics/67_formatter_layout";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
