const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/76X_callback_once_body" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/76X_callback_once_body", "no visible concrete CFunction body matches", "failed without a diagnostic");
}
