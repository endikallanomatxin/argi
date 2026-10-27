const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/219_virtual_preservation_allows_self_mutation" {
    const test_path = "tests/feature_tests/ownership/219_virtual_preservation_allows_self_mutation";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
