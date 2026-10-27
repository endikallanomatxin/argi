const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/109_trusted_opaque_move_scalar" {
    const test_path = "tests/feature_tests/ownership/109_trusted_opaque_move_scalar";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 42);
}
