const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "tests/feature_tests/execution/224_zero_sized_allocation_slots" {
    try expectSuccessfulBuild("tests/feature_tests/execution/224_zero_sized_allocation_slots");
    try runExpect("tests/feature_tests/execution/224_zero_sized_allocation_slots", 42);
    try vmExpect("tests/feature_tests/execution/224_zero_sized_allocation_slots", 42, null);
}
