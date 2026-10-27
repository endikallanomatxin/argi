const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/48_structural_field_move" {
    const test_path = "tests/feature_tests/ownership/48_structural_field_move";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
