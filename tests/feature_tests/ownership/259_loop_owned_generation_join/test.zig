const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/259_loop_owned_generation_join" {
    const test_path = "tests/feature_tests/ownership/259_loop_owned_generation_join";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
