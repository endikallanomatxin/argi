const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/283_scalar_opaque_read_is_independent" {
    const test_path = "tests/feature_tests/ownership/283_scalar_opaque_read_is_independent";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
