const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/80X_allocation_slot_before_storage" {
    const path = "tests/feature_tests/types/80X_allocation_slot_before_storage";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
