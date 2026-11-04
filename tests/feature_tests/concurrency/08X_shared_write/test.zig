const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 08X_shared_write" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/08X_shared_write", "pending execution");
}
