const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/324X_abstract_joint_output_later_invalidation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/324X_abstract_joint_output_later_invalidation", "root that has ended", "failed without a diagnostic");
}
