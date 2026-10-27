const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/39_contextual_nested_array" {
    const path = "tests/feature_tests/basics/39_contextual_nested_array";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
