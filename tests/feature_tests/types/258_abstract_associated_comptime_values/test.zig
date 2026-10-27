const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/258_abstract_associated_comptime_values" {
    const test_path = "tests/feature_tests/types/258_abstract_associated_comptime_values";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
