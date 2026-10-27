const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/200X_returned_symbolic_reference_keeps_written_target" {
    try buildExpectFail("tests/feature_tests/execution/200X_returned_symbolic_reference_keeps_written_target", "root that has ended");
    try vmExpect("tests/feature_tests/execution/200X_returned_symbolic_reference_keeps_written_target", 1, "root that has ended");
}
