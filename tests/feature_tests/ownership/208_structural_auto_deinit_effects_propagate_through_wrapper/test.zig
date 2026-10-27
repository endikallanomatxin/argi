const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/208_structural_auto_deinit_effects_propagate_through_wrapper" {
    const test_path = "tests/feature_tests/ownership/208_structural_auto_deinit_effects_propagate_through_wrapper";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
