const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/209X_symbolic_match_payload_keeps_consumption" {
    try buildExpectFail("tests/feature_tests/execution/209X_symbolic_match_payload_keeps_consumption", "root that has ended");
    try vmExpect("tests/feature_tests/execution/209X_symbolic_match_payload_keeps_consumption", 1, "root that has ended");
}
