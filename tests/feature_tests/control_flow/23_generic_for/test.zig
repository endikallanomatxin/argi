const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/23_generic_for" {
    try expectSuccessfulBuild("tests/feature_tests/control_flow/23_generic_for");
    try runExpect("tests/feature_tests/control_flow/23_generic_for", 0);
}
