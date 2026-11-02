const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/22_loop_transfer_cleanup" {
    try expectSuccessfulBuild("tests/feature_tests/control_flow/22_loop_transfer_cleanup");
    try runExpect("tests/feature_tests/control_flow/22_loop_transfer_cleanup", 0);
}
