const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/147_bit_set_view" {
    try expectSuccessfulBuild("tests/feature_tests/collections/147_bit_set_view");
    try runExpect("tests/feature_tests/collections/147_bit_set_view", 0);
}
