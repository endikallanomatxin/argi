const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/108X_module_condition_nonboolean" {
    try buildExpectFail("tests/feature_tests/execution/108X_module_condition_nonboolean", "compile-time condition requires a Bool result");
}
