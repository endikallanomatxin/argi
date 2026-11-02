const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/156X_virtual_generation_bound_early_return" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/156X_virtual_generation_bound_early_return", "reference depends on a root that has ended");
}
