const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/174_opaque_mark_empty_allows_root_end" {
    const test_path = "tests/feature_tests/ownership/174_opaque_mark_empty_allows_root_end";
    try expectSuccessfulBuild(test_path);
    try runExpect(test_path, 0);
}
