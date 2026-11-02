const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/11_float_classification" {
    try expectSuccessfulBuild("tests/feature_tests/numbers/11_float_classification");
    try runExpect("tests/feature_tests/numbers/11_float_classification", 0);
}
