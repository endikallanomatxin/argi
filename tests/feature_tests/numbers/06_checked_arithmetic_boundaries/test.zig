const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/06_checked_arithmetic_boundaries" {
    try expectSuccessfulBuild("tests/feature_tests/numbers/06_checked_arithmetic_boundaries");
    try runExpect("tests/feature_tests/numbers/06_checked_arithmetic_boundaries", 0);
}
