const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/365X_projected_call_keeps_copy_stale" {
    try buildExpectFail("tests/feature_tests/ownership/365X_projected_call_keeps_copy_stale", "reference depends on a root that has ended");
}
