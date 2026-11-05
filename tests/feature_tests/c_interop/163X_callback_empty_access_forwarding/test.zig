const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 163X_callback_empty_access_forwarding" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/163X_callback_empty_access_forwarding", "method 'run' violates its safety contract");
}
