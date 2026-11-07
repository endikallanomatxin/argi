const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "141X_zero_sized_borrow_move" {
    const path = "tests/feature_tests/concurrency/141X_zero_sized_borrow_move";
    try support.expectFrontendFailure(path, "pending execution");
}
