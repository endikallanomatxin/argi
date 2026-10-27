const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/306X_input_choice_selected_expired_reference" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/306X_input_choice_selected_expired_reference", "root that has ended", "failed without a diagnostic");
}
