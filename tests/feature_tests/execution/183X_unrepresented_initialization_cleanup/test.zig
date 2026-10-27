const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/183X_unrepresented_initialization_cleanup" {
    try buildExpectFail("tests/feature_tests/execution/183X_unrepresented_initialization_cleanup", "cannot select cleanup for conditional initialization");
    try vmExpect("tests/feature_tests/execution/183X_unrepresented_initialization_cleanup", 1, "cannot select cleanup for conditional initialization");
}
