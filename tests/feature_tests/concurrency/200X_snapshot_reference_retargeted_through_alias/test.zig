const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "200X_snapshot_reference_retargeted_through_alias" {
    const path = "tests/feature_tests/concurrency/200X_snapshot_reference_retargeted_through_alias";
    try support.expectFrontendFailure(path, "pending execution");
}
