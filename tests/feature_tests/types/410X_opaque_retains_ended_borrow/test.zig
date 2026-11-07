const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "410X_opaque_retains_ended_borrow" {
    const path = "tests/feature_tests/types/410X_opaque_retains_ended_borrow";
    try support.expectFrontendFailure(path, "ended");
}
