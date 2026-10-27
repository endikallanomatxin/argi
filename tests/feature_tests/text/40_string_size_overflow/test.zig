const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/40_string_size_overflow" {
    const path = "tests/feature_tests/text/40_string_size_overflow";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
