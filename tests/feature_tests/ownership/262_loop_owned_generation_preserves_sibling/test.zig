const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/262_loop_owned_generation_preserves_sibling" {
    const test_path = "tests/feature_tests/ownership/262_loop_owned_generation_preserves_sibling";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
