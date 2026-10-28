const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/74_network_errors" {
    try expectSuccessfulBuild("tests/feature_tests/system/74_network_errors");
    try runExpect("tests/feature_tests/system/74_network_errors", 0);
}
