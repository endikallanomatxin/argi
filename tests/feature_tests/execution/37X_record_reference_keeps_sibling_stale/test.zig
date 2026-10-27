const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/37X_record_reference_keeps_sibling_stale" {
    try buildExpectFail("tests/feature_tests/execution/37X_record_reference_keeps_sibling_stale", "reference depends on a root that has ended");
}
