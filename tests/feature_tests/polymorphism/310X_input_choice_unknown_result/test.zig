const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/310X_input_choice_unknown_result" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/310X_input_choice_unknown_result", "root that has ended", "failed without a diagnostic");
}
