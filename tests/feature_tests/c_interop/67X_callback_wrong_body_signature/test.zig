const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/67X_callback_wrong_body_signature" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/67X_callback_wrong_body_signature", "no visible concrete CFunction body matches", "failed without a diagnostic");
}
