const support = @import("../../../support.zig");
const expectSuccessfulBuild = support.expectSuccessfulBuild;
const runExpect = support.runExpect;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/130_partial_record_indirect_replacement" {
    try expectSuccessfulBuild("tests/feature_tests/execution/130_partial_record_indirect_replacement");
    try runExpect("tests/feature_tests/execution/130_partial_record_indirect_replacement", 42);
    try vmExpect("tests/feature_tests/execution/130_partial_record_indirect_replacement", 42, null);
}
