const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/68_contextual_array_stores" {
    const path = "tests/feature_tests/basics/68_contextual_array_stores";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
