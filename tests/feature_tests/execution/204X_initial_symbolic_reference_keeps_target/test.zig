const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/204X_initial_symbolic_reference_keeps_target" {
    try buildExpectFail("tests/feature_tests/execution/204X_initial_symbolic_reference_keeps_target", "root that has ended");
    try vmExpect("tests/feature_tests/execution/204X_initial_symbolic_reference_keeps_target", 1, "root that has ended");
}
