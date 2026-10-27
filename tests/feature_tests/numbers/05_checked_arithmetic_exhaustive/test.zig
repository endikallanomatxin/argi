const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/05_checked_arithmetic_exhaustive" {
    try expectSuccessfulBuild("tests/feature_tests/numbers/05_checked_arithmetic_exhaustive");
    try runExpect("tests/feature_tests/numbers/05_checked_arithmetic_exhaustive", 0);
}
