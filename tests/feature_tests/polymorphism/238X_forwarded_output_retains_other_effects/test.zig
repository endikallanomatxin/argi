const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/238X_forwarded_output_retains_other_effects" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/238X_forwarded_output_retains_other_effects", "reference depends on a root that has ended");
}
