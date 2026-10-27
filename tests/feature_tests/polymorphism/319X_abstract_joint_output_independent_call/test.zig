const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/319X_abstract_joint_output_independent_call" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/319X_abstract_joint_output_independent_call", "root that has ended", "failed without a diagnostic");
}
