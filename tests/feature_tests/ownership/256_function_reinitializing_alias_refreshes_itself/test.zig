const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/256_function_reinitializing_alias_refreshes_itself" {
    const test_path = "tests/feature_tests/ownership/256_function_reinitializing_alias_refreshes_itself";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
