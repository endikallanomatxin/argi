const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/70X_computed_nonboolean_condition" {
    try buildExpectFail("tests/feature_tests/execution/70X_computed_nonboolean_condition", "compile-time condition requires a Bool result");
}
