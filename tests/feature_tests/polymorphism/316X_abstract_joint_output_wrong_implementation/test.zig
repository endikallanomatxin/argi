const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/316X_abstract_joint_output_wrong_implementation" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/316X_abstract_joint_output_wrong_implementation", "safety contract", "failed without a diagnostic");
}
