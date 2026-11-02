const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/65X_enum_constant_expression" {
    try support.expectSyntaxFailureWithoutNoise("tests/feature_tests/c_interop/65X_enum_constant_expression", "constant expressions are not supported", "failed without a diagnostic");
}
