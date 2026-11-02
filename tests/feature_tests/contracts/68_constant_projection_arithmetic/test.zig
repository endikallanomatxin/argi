const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/68_constant_projection_arithmetic" {
    const test_path = "tests/feature_tests/contracts/68_constant_projection_arithmetic";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
