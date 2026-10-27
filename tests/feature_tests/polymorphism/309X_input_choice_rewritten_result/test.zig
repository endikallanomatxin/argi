const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/309X_input_choice_rewritten_result" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/309X_input_choice_rewritten_result", "root that has ended", "failed without a diagnostic");
}
