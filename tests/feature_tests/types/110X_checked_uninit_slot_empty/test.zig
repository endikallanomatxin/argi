const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/110X_checked_uninit_slot_empty" {
    const path = "tests/feature_tests/types/110X_checked_uninit_slot_empty";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
