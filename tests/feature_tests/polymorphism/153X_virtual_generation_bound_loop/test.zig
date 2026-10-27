const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/153X_virtual_generation_bound_loop" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/153X_virtual_generation_bound_loop", "reference depends on a root that has ended");
}
