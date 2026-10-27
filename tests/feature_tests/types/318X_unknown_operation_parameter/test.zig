const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/318X_unknown_operation_parameter" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/318X_unknown_operation_parameter", "unknown compile-time argument", "without a diagnostic");
}
