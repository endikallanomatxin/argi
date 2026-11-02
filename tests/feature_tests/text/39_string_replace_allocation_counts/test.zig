const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/39_string_replace_allocation_counts" {
    const path = "tests/feature_tests/text/39_string_replace_allocation_counts";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
