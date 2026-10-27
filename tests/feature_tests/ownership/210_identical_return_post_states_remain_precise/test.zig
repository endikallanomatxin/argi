const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/210_identical_return_post_states_remain_precise" {
    const test_path = "tests/feature_tests/ownership/210_identical_return_post_states_remain_precise";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
