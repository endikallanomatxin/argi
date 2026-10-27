const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/214X_conditional_relocates_unselected" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/214X_conditional_relocates_unselected", "maybe_initialized and cannot be used");
}
