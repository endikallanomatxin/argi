const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/198X_symbolic_reference_values_survive_conditional_calls" {
    try buildExpectFail("tests/feature_tests/execution/198X_symbolic_reference_values_survive_conditional_calls", "root that has ended");
    try vmExpect("tests/feature_tests/execution/198X_symbolic_reference_values_survive_conditional_calls", 1, "root that has ended");
}
