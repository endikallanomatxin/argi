const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/c_interop/131X_generic_c_function_definition_value" {
    try buildExpectFailWithoutNoise("tests/feature_tests/c_interop/131X_generic_c_function_definition_value", "CFunction requires a concrete non-generic definition", "without a diagnostic");
}
