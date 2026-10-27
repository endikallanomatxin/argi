const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/166X_indexed_replacement_keeps_alias_stale" {
    try buildExpectFail("tests/feature_tests/execution/166X_indexed_replacement_keeps_alias_stale", "root that has ended");
}
