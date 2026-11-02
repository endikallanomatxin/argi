const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/138_opaque_hidden_dependency_allows_unrelated_owner_consumption" {
    const test_path = "tests/feature_tests/ownership/138_opaque_hidden_dependency_allows_unrelated_owner_consumption";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
