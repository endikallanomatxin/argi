const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/106_trusted_opaque_move_user_call" {
    const test_path = "tests/feature_tests/ownership/106_trusted_opaque_move_user_call";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
