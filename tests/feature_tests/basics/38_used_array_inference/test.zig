const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/38_used_array_inference" {
    const path = "tests/feature_tests/basics/38_used_array_inference";
    try expectSuccessfulBuild(path);
    try runExpect(path, 1);
}
