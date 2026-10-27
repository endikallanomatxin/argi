const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/83X_allocation_slot_misaligned" {
    const path = "tests/feature_tests/types/83X_allocation_slot_misaligned";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
