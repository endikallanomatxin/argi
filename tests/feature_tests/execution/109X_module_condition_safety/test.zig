const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/109X_module_condition_safety" {
    try buildExpectFail("tests/feature_tests/execution/109X_module_condition_safety", "deinitialized");
}
