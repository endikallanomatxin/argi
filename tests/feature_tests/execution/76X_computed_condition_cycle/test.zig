const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/76X_computed_condition_cycle" {
    try buildExpectFail("tests/feature_tests/execution/76X_computed_condition_cycle", "unresolved or cyclic semantic dependencies");
}
