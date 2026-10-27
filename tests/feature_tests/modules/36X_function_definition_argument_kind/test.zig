const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/36X_function_definition_argument_kind" {
    try buildExpectFailWithoutNoise("tests/feature_tests/modules/36X_function_definition_argument_kind", "compile-time argument kind does not match the definition parameter", "failed without a diagnostic");
}
