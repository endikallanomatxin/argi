const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/316X_abstract_joint_output_wrong_implementation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/316X_abstract_joint_output_wrong_implementation", "safety contract", "failed without a diagnostic");
}
