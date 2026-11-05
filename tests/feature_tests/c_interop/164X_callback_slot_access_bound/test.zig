const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 164X_callback_slot_access_bound" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/164X_callback_slot_access_bound", "method 'run' violates its safety contract");
}
