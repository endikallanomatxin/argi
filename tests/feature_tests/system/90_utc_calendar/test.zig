const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/system/90_utc_calendar" {
    try expectSuccessfulBuild("tests/feature_tests/system/90_utc_calendar");
    try runExpect("tests/feature_tests/system/90_utc_calendar", 0);
}
