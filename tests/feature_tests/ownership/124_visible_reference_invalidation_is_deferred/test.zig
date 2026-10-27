const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/124_visible_reference_invalidation_is_deferred" {
    const test_path = "tests/feature_tests/ownership/124_visible_reference_invalidation_is_deferred";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
