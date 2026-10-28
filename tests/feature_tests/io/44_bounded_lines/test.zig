const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/io/44_bounded_lines" {
    try expectSuccessfulBuild("tests/feature_tests/io/44_bounded_lines");
    try runExpect("tests/feature_tests/io/44_bounded_lines", 0);
}
