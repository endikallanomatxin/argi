const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/285_reference_can_erase_to_any" {
    const test_path = "tests/feature_tests/ownership/285_reference_can_erase_to_any";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
