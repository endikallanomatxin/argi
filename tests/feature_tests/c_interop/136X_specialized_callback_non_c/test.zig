const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "136X_specialized_callback_non_c" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/136X_specialized_callback_non_c", "no visible concrete CFunction body matches the callback signature", "failed without a diagnostic");
}
