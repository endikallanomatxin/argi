const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/61X_enum_value_overflow" {
    try support.expectSyntaxFailureWithoutNoise("tests/feature_tests/c_interop/61X_enum_value_overflow", "CEnum value is outside", "failed without a diagnostic");
}
