const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/69_computed_concrete_condition" {
    try expectSuccessfulBuild("tests/feature_tests/execution/69_computed_concrete_condition");
    try runExpect("tests/feature_tests/execution/69_computed_concrete_condition", 42);
    try vmExpect("tests/feature_tests/execution/69_computed_concrete_condition", 42, null);
}
