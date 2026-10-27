const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/104_partial_owning_array_field" {
    try expectSuccessfulBuild("tests/feature_tests/execution/104_partial_owning_array_field");
    try runExpect("tests/feature_tests/execution/104_partial_owning_array_field", 0);
    try vmExpect("tests/feature_tests/execution/104_partial_owning_array_field", 0, null);
}
