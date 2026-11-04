const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 10X_join_other_future" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/10X_join_other_future", "pending execution");
}
