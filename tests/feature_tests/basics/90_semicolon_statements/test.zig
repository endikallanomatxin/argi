const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/90_semicolon_statements" {
    try expectSuccessfulBuild("tests/feature_tests/basics/90_semicolon_statements");
    try runExpect("tests/feature_tests/basics/90_semicolon_statements", 0);
}
