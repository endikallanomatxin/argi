const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/21X_for_moving_borrow" {
    try buildExpectFail("tests/feature_tests/control_flow/21X_for_moving_borrow", "MovingIterable");
}
