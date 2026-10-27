const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/308X_joint_input_choice_selected_expired_reference" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/308X_joint_input_choice_selected_expired_reference", "root that has ended", "failed without a diagnostic");
}
