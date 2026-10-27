const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/150X_virtual_generation_bound_reassigned" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/150X_virtual_generation_bound_reassigned", "reference depends on a root that has ended");
}
