const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/188X_array_reference_input_historical_copy" {
    try buildExpectFail("tests/feature_tests/execution/188X_array_reference_input_historical_copy", "reference depends on a root that has ended");
    try vmExpect("tests/feature_tests/execution/188X_array_reference_input_historical_copy", 1, "reference depends on a root that has ended");
}
