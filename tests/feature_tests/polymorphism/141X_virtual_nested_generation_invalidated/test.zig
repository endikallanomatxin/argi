const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/141X_virtual_nested_generation_invalidated" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/141X_virtual_nested_generation_invalidated", "reference depends on a root that has ended");
}
