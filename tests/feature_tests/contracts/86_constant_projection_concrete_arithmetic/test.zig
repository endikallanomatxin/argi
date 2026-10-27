const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/86_constant_projection_concrete_arithmetic" {
    const path = "tests/feature_tests/contracts/86_constant_projection_concrete_arithmetic";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
