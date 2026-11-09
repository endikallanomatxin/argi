const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "188X_unknown_virtual_cleanup_pending_writer" {
    const path = "tests/feature_tests/concurrency/188X_unknown_virtual_cleanup_pending_writer";
    try support.expectFrontendFailure(path, "call has unknown memory effects while a pending execution retains borrowed storage");
}
