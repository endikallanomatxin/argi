const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/85_constant_projection_concrete_function" {
    const path = "tests/feature_tests/contracts/85_constant_projection_concrete_function";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
