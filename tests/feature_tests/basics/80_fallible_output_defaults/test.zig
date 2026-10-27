const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/80_fallible_output_defaults" {
    const path = "tests/feature_tests/basics/80_fallible_output_defaults";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
