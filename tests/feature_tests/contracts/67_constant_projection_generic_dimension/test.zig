const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/67_constant_projection_generic_dimension" {
    const test_path = "tests/feature_tests/contracts/67_constant_projection_generic_dimension";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
