const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/261_loop_owned_generation_allows_fresh_alias" {
    const test_path = "tests/feature_tests/ownership/261_loop_owned_generation_allows_fresh_alias";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
