const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 165X_callback_callee_global_access" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/165X_callback_callee_global_access", "method 'run' violates its safety contract");
}
