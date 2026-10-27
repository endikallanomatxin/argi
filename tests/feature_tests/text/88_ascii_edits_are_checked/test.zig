const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/88_ascii_edits_are_checked" {
    try expectSuccessfulBuild("tests/feature_tests/text/88_ascii_edits_are_checked");
    try runExpect("tests/feature_tests/text/88_ascii_edits_are_checked", 0);
}
