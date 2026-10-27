const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/105X_partial_array_reference_lifetime" {
    try buildExpectFail("tests/feature_tests/execution/105X_partial_array_reference_lifetime", "depends on a root that has ended");
    try vmExpect("tests/feature_tests/execution/105X_partial_array_reference_lifetime", 1, "depends on a root that has ended");
}
