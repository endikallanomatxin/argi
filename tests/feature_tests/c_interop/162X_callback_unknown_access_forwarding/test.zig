const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 162X_callback_unknown_access_forwarding" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/162X_callback_unknown_access_forwarding", "method 'run' violates its safety contract");
}
