const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/92_utc_format" {
    try expectSuccessfulBuild("tests/feature_tests/system/92_utc_format");
    try runExpect("tests/feature_tests/system/92_utc_format", 0);
}
