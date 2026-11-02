const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/64X_enum_duplicate_value" {
    try support.expectSyntaxFailureWithoutNoise("tests/feature_tests/c_interop/64X_enum_duplicate_value", "duplicate CEnum numeric values", "failed without a diagnostic");
}
