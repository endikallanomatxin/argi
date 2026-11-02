const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/42_inferred_array_element_types" {
    const path = "tests/feature_tests/basics/42_inferred_array_element_types";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
