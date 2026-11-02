const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/129_opaque_hidden_dependency_does_not_block_unrelated_root" {
    const test_path = "tests/feature_tests/ownership/129_opaque_hidden_dependency_does_not_block_unrelated_root";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
