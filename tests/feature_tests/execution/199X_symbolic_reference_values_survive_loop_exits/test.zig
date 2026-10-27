const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/199X_symbolic_reference_values_survive_loop_exits" {
    try buildExpectFail("tests/feature_tests/execution/199X_symbolic_reference_values_survive_loop_exits", "root that has ended");
    try vmExpect("tests/feature_tests/execution/199X_symbolic_reference_values_survive_loop_exits", 1, "root that has ended");
}
