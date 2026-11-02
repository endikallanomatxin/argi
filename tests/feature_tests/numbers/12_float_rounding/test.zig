const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/12_float_rounding" {
    try expectSuccessfulBuild("tests/feature_tests/numbers/12_float_rounding");
    try runExpect("tests/feature_tests/numbers/12_float_rounding", 0);
}
