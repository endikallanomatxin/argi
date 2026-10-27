const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/14_for_mut_borrowed_dynamic_array" {
    const test_path = "tests/feature_tests/control_flow/14_for_mut_borrowed_dynamic_array";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
