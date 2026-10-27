const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/325X_abstract_input_choice_wrong_implementation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/325X_abstract_input_choice_wrong_implementation", "undeclared output dependency", "failed without a diagnostic");
}
