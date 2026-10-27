const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/15_logical_and_or" {
    const test_path = "tests/feature_tests/control_flow/15_logical_and_or";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
