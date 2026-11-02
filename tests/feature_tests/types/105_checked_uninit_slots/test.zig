const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/105_checked_uninit_slots" {
    const path = "tests/feature_tests/types/105_checked_uninit_slots";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
