const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/52X_incomplete_parameters" {
    try support.expectSyntaxFailureWithoutNoise("tests/feature_tests/c_interop/52X_incomplete_parameters", "cannot have compile-time parameters", "failed without a diagnostic");
}
