const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/106X_checked_uninit_slot_extent" {
    const path = "tests/feature_tests/types/106X_checked_uninit_slot_extent";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
