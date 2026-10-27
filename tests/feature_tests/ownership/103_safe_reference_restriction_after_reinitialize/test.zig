const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/103_safe_reference_restriction_after_reinitialize" {
    const test_path = "tests/feature_tests/ownership/103_safe_reference_restriction_after_reinitialize";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
