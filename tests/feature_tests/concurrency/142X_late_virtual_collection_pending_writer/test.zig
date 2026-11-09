const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "142X_late_virtual_collection_pending_writer" {
    const path = "tests/feature_tests/concurrency/142X_late_virtual_collection_pending_writer";
    try support.expectFrontendFailure(path, "pending execution");
}
