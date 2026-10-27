const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/342X_once_generic_value_reuse" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/342X_once_generic_value_reuse", "is consumed more than once", "without a diagnostic");
}
