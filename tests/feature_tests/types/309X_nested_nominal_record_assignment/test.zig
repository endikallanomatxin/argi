const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/309X_nested_nominal_record_assignment" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/309X_nested_nominal_record_assignment", "distinct nominal types require explicit conversion", "without a diagnostic");
}
