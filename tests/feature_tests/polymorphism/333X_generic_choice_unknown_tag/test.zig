const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/333X_generic_choice_unknown_tag" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/333X_generic_choice_unknown_tag", "no generic function named 'invalid'", "failed without a diagnostic");
}
