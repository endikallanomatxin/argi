const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/36_error_propagation_if_condition" {
    const test_path = "tests/feature_tests/types/36_error_propagation_if_condition";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 1);
}
