const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/111X_checked_uninit_slot_overflow" {
    const path = "tests/feature_tests/types/111X_checked_uninit_slot_overflow";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
