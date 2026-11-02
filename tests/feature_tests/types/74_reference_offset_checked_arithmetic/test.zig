const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/74_reference_offset_checked_arithmetic" {
    const path = "tests/feature_tests/types/74_reference_offset_checked_arithmetic";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
