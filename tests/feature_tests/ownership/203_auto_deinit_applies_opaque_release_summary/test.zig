const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/203_auto_deinit_applies_opaque_release_summary" {
    const test_path = "tests/feature_tests/ownership/203_auto_deinit_applies_opaque_release_summary";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
