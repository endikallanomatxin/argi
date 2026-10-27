const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "feature_tests/c_interop/68X_callback_argi_body" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/68X_callback_argi_body", "no visible concrete CFunction body matches", "failed without a diagnostic");
}
