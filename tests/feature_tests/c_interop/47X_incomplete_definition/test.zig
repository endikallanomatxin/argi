const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/47X_incomplete_definition" {
    try support.expectSyntaxFailureWithoutNoise("tests/feature_tests/c_interop/47X_incomplete_definition", "omit the definition", "failed without a diagnostic");
}
