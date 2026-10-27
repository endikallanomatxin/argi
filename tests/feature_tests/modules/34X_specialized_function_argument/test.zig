const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/34X_specialized_function_argument" {
    try buildExpectFailWithoutNoise("tests/feature_tests/modules/34X_specialized_function_argument", "arguments do not match this specialized function definition", "failed without a diagnostic");
}
