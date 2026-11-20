const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;

test "294X_root_array_backing_conflicting_loan" {
    const path = "tests/feature_tests/concurrency/294X_root_array_backing_conflicting_loan";
    try support.expectFrontendFailure(path, "concurrent access conflicts with a pending execution");
}
