const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/106X_partial_array_explicit_dependency" {
    try buildExpectFail("tests/feature_tests/execution/106X_partial_array_explicit_dependency", "depends on a root that has ended");
    try vmExpect("tests/feature_tests/execution/106X_partial_array_explicit_dependency", 1, "depends on a root that has ended");
}
