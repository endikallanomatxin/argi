const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/20X_for_moving_reuse" {
    try buildExpectFail("tests/feature_tests/control_flow/20X_for_moving_reuse", "moved");
}
