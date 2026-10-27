const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/100X_completed_record_stale_reference" {
    try buildExpectFail("tests/feature_tests/execution/100X_completed_record_stale_reference", "reference depends on a root that has ended");
    try vmExpect("tests/feature_tests/execution/100X_completed_record_stale_reference", 1, "reference depends on a root that has ended");
}
