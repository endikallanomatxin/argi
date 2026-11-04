const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 07X_exclusive_alias_write" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/07X_exclusive_alias_write", "pending execution");
}
