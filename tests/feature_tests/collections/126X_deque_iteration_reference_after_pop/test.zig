const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/126X_deque_iteration_reference_after_pop" {
    try expectFrontendFailure("tests/feature_tests/collections/126X_deque_iteration_reference_after_pop", "root that has ended");
}
