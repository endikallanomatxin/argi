const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/46_whitespace_tokens" {
    try expectSuccessfulBuild("tests/feature_tests/text/46_whitespace_tokens");
    try runExpect("tests/feature_tests/text/46_whitespace_tokens", 0);
}
