const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/61_explicit_integer_conversions" {
    const path = "tests/feature_tests/basics/61_explicit_integer_conversions";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
