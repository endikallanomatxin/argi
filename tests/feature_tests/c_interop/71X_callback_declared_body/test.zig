const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/71X_callback_declared_body" {
    try support.expectSyntaxFailureWithoutNoise("tests/feature_tests/c_interop/71X_callback_declared_body", "without symbol options or a body", "failed without a diagnostic");
}
