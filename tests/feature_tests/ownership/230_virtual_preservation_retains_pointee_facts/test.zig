const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/230_virtual_preservation_retains_pointee_facts" {
    const test_path = "tests/feature_tests/ownership/230_virtual_preservation_retains_pointee_facts";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
