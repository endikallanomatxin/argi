const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/48_checked_string_slice" {
    try expectSuccessfulBuild("tests/feature_tests/text/48_checked_string_slice");
    try runExpect("tests/feature_tests/text/48_checked_string_slice", 0);
}
