const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/324X_abstract_joint_output_later_invalidation" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/324X_abstract_joint_output_later_invalidation", "root that has ended", "failed without a diagnostic");
}
