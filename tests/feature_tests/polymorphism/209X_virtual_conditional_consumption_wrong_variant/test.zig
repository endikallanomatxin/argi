const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/209X_virtual_conditional_consumption_wrong_variant" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/209X_virtual_conditional_consumption_wrong_variant", "storage transition is not permitted");
}
