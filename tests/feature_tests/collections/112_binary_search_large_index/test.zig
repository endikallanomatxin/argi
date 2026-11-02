const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/112_binary_search_large_index" {
    const path = "tests/feature_tests/collections/112_binary_search_large_index";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
