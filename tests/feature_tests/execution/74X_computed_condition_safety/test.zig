const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/74X_computed_condition_safety" {
    try buildExpectFail("tests/feature_tests/execution/74X_computed_condition_safety", "consumption requires an initialized owner");
}
