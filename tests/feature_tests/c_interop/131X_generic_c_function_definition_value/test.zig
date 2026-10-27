const support = @import("../../../support.zig");
const expectSyntaxFailureWithoutNoise = support.expectSyntaxFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/131X_generic_c_function_definition_value" {
    try expectSyntaxFailureWithoutNoise("tests/feature_tests/c_interop/131X_generic_c_function_definition_value", "CFunction requires a concrete non-generic definition", "without a diagnostic");
}
