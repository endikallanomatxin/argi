const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/63X_enum_value_not_integer" {
    try support.expectSyntaxFailureWithoutNoise("tests/feature_tests/c_interop/63X_enum_value_not_integer", "CEnum value must be an Int32 integer literal", "failed without a diagnostic");
}
