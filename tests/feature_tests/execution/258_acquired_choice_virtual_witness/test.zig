const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/258_acquired_choice_virtual_witness" {
    try expectSuccessfulBuild("tests/feature_tests/execution/258_acquired_choice_virtual_witness");
    try runExpect("tests/feature_tests/execution/258_acquired_choice_virtual_witness", 42);
    try vmExpect("tests/feature_tests/execution/258_acquired_choice_virtual_witness", 42, null);
}
