const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 101X_concurrent_helper_read_aliases_writer" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/101X_concurrent_helper_read_aliases_writer", "concurrent access conflicts through aliased function inputs");
}
