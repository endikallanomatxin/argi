const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/92_constant_projection_mixed_concrete_arguments" {
    const path = "tests/feature_tests/contracts/92_constant_projection_mixed_concrete_arguments";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
