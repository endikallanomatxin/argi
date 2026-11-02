const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/204X_conditional_consumption_stale_result" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/204X_conditional_consumption_stale_result", "maybe_initialized");
}
