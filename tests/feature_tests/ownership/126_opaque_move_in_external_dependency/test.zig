const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/126_opaque_move_in_external_dependency" {
    const test_path = "tests/feature_tests/ownership/126_opaque_move_in_external_dependency";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
