const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/293_resource_state_protocol" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/293_resource_state_protocol");
    try runExpect("tests/feature_tests/contracts/293_resource_state_protocol", 0);
}
