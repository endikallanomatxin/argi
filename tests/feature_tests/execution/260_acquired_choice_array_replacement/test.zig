const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/260_acquired_choice_array_replacement" {
    try expectSuccessfulBuild("tests/feature_tests/execution/260_acquired_choice_array_replacement");
    try runExpect("tests/feature_tests/execution/260_acquired_choice_array_replacement", 42);
    try vmExpect("tests/feature_tests/execution/260_acquired_choice_array_replacement", 42, null);
}
