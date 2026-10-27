const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/195X_conditional_consumption_unselected_cleanup" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/195X_conditional_consumption_unselected_cleanup", "cannot select cleanup for conditional consumption");
}
