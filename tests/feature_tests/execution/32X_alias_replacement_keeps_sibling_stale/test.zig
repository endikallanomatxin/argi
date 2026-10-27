const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/32X_alias_replacement_keeps_sibling_stale" {
    try buildExpectFail("tests/feature_tests/execution/32X_alias_replacement_keeps_sibling_stale", "reference depends on a root that has ended");
    try vmExpect("tests/feature_tests/execution/32X_alias_replacement_keeps_sibling_stale", 1, "reference depends on a root that has ended");
}
