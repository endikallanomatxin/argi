const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/79_allocation_slot_range_checks" {
    const path = "tests/feature_tests/types/79_allocation_slot_range_checks";
    try expectSuccessfulBuild(path);
    try runExpect(path, 0);
}
