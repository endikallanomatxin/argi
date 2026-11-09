const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency/138X_loop_reference_retarget_pending_writer" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/138X_loop_reference_retarget_pending_writer", "call has unknown memory effects while a pending execution retains borrowed storage");
}
