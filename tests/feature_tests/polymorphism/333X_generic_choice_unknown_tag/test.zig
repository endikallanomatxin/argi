const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/333X_generic_choice_unknown_tag" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/333X_generic_choice_unknown_tag", "no generic function named 'invalid'", "failed without a diagnostic");
}
