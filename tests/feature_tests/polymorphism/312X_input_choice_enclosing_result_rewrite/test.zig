const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/312X_input_choice_enclosing_result_rewrite" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/312X_input_choice_enclosing_result_rewrite", "root that has ended", "failed without a diagnostic");
}
