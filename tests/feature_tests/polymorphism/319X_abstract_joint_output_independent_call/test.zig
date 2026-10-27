const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/319X_abstract_joint_output_independent_call" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/319X_abstract_joint_output_independent_call", "root that has ended", "failed without a diagnostic");
}
