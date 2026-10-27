const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/14_if_break_only_codegen" {
    const test_path = "tests/feature_tests/control_flow/14_if_break_only_codegen";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
