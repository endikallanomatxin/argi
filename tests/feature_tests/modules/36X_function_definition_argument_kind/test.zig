const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/modules/36X_function_definition_argument_kind" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/modules/36X_function_definition_argument_kind", "compile-time argument kind does not match the definition parameter", "failed without a diagnostic");
}
