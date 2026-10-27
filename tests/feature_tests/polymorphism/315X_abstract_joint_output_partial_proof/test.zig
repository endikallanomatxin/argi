const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/315X_abstract_joint_output_partial_proof" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/315X_abstract_joint_output_partial_proof", "root that has ended", "failed without a diagnostic");
}
