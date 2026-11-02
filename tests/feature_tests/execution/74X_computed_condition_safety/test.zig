const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/74X_computed_condition_safety" {
    try expectFrontendFailure("tests/feature_tests/execution/74X_computed_condition_safety", "consumption requires an initialized owner");
}
