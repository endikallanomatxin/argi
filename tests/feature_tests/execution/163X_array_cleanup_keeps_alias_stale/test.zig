const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/163X_array_cleanup_keeps_alias_stale" {
    try buildExpectFail("tests/feature_tests/execution/163X_array_cleanup_keeps_alias_stale", "root that has ended");
}
