const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/17_forward_call_output_field_access_in_if" {
    const test_path = "tests/feature_tests/control_flow/17_forward_call_output_field_access_in_if";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
