const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/basics/30_numeric_contextual_assignment" {
    const path = "tests/feature_tests/basics/30_numeric_contextual_assignment";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
