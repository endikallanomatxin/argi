const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/135_opaque_move_in_exactly_once_codegen" {
    const test_path = "tests/feature_tests/ownership/135_opaque_move_in_exactly_once_codegen";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
