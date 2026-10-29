const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/24_string_view_search" {
    const path = "tests/feature_tests/text/24_string_view_search";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
    try support.vmExpect(path, 0, null);
}
