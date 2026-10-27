const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/319X_excess_operation_parameters" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/319X_excess_operation_parameters", "too many compile-time arguments", "without a diagnostic");
}
