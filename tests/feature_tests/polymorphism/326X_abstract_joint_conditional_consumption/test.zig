const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/326X_abstract_joint_conditional_consumption" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/326X_abstract_joint_conditional_consumption", "joint choice conditions cannot conditionally consume or relocate owners", "failed without a diagnostic");
}
