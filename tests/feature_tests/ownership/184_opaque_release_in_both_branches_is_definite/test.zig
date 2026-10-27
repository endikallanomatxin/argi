const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/184_opaque_release_in_both_branches_is_definite" {
    const test_path = "tests/feature_tests/ownership/184_opaque_release_in_both_branches_is_definite";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
