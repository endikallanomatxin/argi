const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "specialized once function cannot become a callback" {
    try support.expectFrontendFailureWithoutNoise("tests/feature_tests/c_interop/139X_specialized_callback_once", "no visible concrete CFunction body matches", "failed without a diagnostic");
}
