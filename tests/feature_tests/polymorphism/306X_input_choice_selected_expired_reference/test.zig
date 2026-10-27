const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/306X_input_choice_selected_expired_reference" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/306X_input_choice_selected_expired_reference", "root that has ended", "failed without a diagnostic");
}
