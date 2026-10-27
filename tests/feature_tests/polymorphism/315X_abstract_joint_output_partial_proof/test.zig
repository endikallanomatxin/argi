const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/315X_abstract_joint_output_partial_proof" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/315X_abstract_joint_output_partial_proof", "root that has ended", "failed without a diagnostic");
}
