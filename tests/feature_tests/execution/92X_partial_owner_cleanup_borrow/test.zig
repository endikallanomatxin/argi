const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/92X_partial_owner_cleanup_borrow" {
    try buildExpectFail("tests/feature_tests/execution/92X_partial_owner_cleanup_borrow", "reference depends on a root that has ended");
    try vmExpect("tests/feature_tests/execution/92X_partial_owner_cleanup_borrow", 1, "reference depends on a root that has ended");
}
