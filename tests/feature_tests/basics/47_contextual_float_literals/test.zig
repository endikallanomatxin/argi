const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/47_contextual_float_literals" {
    const path = "tests/feature_tests/basics/47_contextual_float_literals";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
