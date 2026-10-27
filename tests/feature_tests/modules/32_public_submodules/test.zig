const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/32_public_submodules" {
    try expectSuccessfulBuild("tests/feature_tests/modules/32_public_submodules");
    try runExpect("tests/feature_tests/modules/32_public_submodules", 0);
}
