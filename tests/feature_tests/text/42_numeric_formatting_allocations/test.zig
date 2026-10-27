const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/42_numeric_formatting_allocations" {
    const path = "tests/feature_tests/text/42_numeric_formatting_allocations";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
