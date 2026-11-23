const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "322X_virtual_cleanup_after_unrelated_join" {
    try support.expectFrontendFailure(
        "tests/feature_tests/concurrency/322X_virtual_cleanup_after_unrelated_join",
        "concurrent access conflicts with a pending execution",
    );
}
