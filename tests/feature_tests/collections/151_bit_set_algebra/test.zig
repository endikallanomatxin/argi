const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/151_bit_set_algebra" {
    try expectSuccessfulBuild("tests/feature_tests/collections/151_bit_set_algebra");
    try runExpect("tests/feature_tests/collections/151_bit_set_algebra", 0);
}
