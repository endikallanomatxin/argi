const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "C interop 166X_callback_invalid_unused_bound" {
    try support.expectFrontendFailure("tests/feature_tests/c_interop/166X_callback_invalid_unused_bound", "invalid callback access contract: reads and writes require a reference input");
}
