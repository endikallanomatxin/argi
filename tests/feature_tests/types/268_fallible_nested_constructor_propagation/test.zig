const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/268_fallible_nested_constructor_propagation" {
    const test_path = "tests/feature_tests/types/268_fallible_nested_constructor_propagation";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
