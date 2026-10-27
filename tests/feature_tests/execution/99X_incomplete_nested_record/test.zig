const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/99X_incomplete_nested_record" {
    try buildExpectFail("tests/feature_tests/execution/99X_incomplete_nested_record", "deinitialized");
}
