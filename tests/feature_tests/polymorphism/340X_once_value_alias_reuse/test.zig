const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/340X_once_value_alias_reuse" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/340X_once_value_alias_reuse", "once function 'acquire' is consumed more than once", "without a diagnostic");
}
