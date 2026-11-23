const support = @import("../../../support.zig");

pub const isolation: support.Isolation = .fixture;

test "326X_remaining_reader_blocks_cleanup" {
    try support.expectFrontendFailure(
        "tests/feature_tests/concurrency/326X_remaining_reader_blocks_cleanup",
        "concurrent access conflicts with a pending execution",
    );
}
