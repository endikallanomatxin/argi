const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/71X_computed_runtime_condition" {
    try buildExpectFail("tests/feature_tests/execution/71X_computed_runtime_condition", "runtime values cannot be used");
}
