const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/35_system_move_by_value" {
    const test_path = "tests/feature_tests/ownership/35_system_move_by_value";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
