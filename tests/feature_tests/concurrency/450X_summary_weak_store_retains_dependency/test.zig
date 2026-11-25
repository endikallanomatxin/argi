const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "450X_summary_weak_store_retains_dependency" {
    const path = "tests/feature_tests/concurrency/450X_summary_weak_store_retains_dependency";
    try support.expectFrontendFailure(path, "reference depends on a root that has ended");
}
