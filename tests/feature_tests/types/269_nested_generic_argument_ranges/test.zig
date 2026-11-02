const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/269_nested_generic_argument_ranges" {
    const path = "tests/feature_tests/types/269_nested_generic_argument_ranges";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
