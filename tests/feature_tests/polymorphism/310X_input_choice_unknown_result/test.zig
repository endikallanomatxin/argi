const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "tests/feature_tests/polymorphism/310X_input_choice_unknown_result" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/310X_input_choice_unknown_result", "root that has ended", "failed without a diagnostic");
}
