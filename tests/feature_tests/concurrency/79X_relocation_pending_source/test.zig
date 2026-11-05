const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 79X_relocation_pending_source" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/79X_relocation_pending_source", "concurrent access conflicts with a pending execution");
}
