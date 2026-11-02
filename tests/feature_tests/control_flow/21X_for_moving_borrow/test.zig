const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/21X_for_moving_borrow" {
    try expectFrontendFailure("tests/feature_tests/control_flow/21X_for_moving_borrow", "MovingIterable");
}
