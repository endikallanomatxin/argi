const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/326X_abstract_joint_conditional_consumption" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/326X_abstract_joint_conditional_consumption", "joint choice conditions cannot conditionally consume or relocate owners", "failed without a diagnostic");
}
