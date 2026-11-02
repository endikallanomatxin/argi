const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpectFailure = support.runExpectFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/82X_allocation_slot_crosses_storage_end" {
    const path = "tests/feature_tests/types/82X_allocation_slot_crosses_storage_end";
    try expectSuccessfulBuild(path);
    try runExpectFailure(path);
}
