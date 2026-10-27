const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/62_integer_conversion_ranges" {
    const path = "tests/feature_tests/basics/62_integer_conversion_ranges";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
