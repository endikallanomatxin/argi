const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/328_ordered_scalar_nan" {
    try expectSuccessfulBuild("tests/feature_tests/contracts/328_ordered_scalar_nan");
    try runExpect("tests/feature_tests/contracts/328_ordered_scalar_nan", 0);
}
