const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "concurrency 14X_move_owner" {
    try support.expectFrontendFailure("tests/feature_tests/concurrency/14X_move_owner", "pending execution");
}
