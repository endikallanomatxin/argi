const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/317X_abstract_joint_output_overwritten_selector" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/317X_abstract_joint_output_overwritten_selector", "root that has ended", "failed without a diagnostic");
}
