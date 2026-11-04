const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 06X_exclusive_alias_read" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/06X_exclusive_alias_read", "pending execution");
}
