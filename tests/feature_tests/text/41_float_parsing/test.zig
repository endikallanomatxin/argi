const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/41_float_parsing" {
    const path = "tests/feature_tests/text/41_float_parsing";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
