const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/149_owned_bit_set" {
    try expectSuccessfulBuild("tests/feature_tests/collections/149_owned_bit_set");
    try runExpect("tests/feature_tests/collections/149_owned_bit_set", 0);
}
