const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "279X_virtual_cleanup_conflicts_with_loan" {
    try support.expectFrontendFailure(
        "tests/feature_tests/concurrency/279X_virtual_cleanup_conflicts_with_loan",
        "concurrent access conflicts with a pending execution",
    );
}
