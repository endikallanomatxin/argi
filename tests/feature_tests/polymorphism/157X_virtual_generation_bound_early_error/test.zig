const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/157X_virtual_generation_bound_early_error" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/157X_virtual_generation_bound_early_error", "reference depends on a root that has ended");
}
