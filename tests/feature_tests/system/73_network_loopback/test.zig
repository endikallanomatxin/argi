const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/73_network_loopback" {
    try expectSuccessfulBuild("tests/feature_tests/system/73_network_loopback");
    try runExpect("tests/feature_tests/system/73_network_loopback", 0);
}
