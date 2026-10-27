const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/75_computed_module_condition" {
    try expectSuccessfulBuild("tests/feature_tests/execution/75_computed_module_condition");
    try runExpect("tests/feature_tests/execution/75_computed_module_condition", 42);
    try vmExpect("tests/feature_tests/execution/75_computed_module_condition", 42, null);
}
