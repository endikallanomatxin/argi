const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/325X_abstract_input_choice_wrong_implementation" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/325X_abstract_input_choice_wrong_implementation", "undeclared output dependency", "failed without a diagnostic");
}
