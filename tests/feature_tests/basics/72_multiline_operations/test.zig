const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/72_multiline_operations" {
    const path = "tests/feature_tests/basics/72_multiline_operations";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
