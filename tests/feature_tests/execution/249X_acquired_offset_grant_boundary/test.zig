const support = @import("../../../support.zig");
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/249X_acquired_offset_grant_boundary" {
    try vmExpect("tests/feature_tests/execution/249X_acquired_offset_grant_boundary", 1, "ExecutionIndexOutOfBounds");
}
