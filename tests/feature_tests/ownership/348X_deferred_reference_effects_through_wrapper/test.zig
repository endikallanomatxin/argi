const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/348X_deferred_reference_effects_through_wrapper" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/ownership/348X_deferred_reference_effects_through_wrapper", "reference depends on a root that has ended");
}
