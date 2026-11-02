const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/84X_allocation_slot_empty_storage" {
    const path = "tests/feature_tests/types/84X_allocation_slot_empty_storage";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
