const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "414X_opaque_ended_borrow_generic_wrapper" {
    const path = "tests/feature_tests/types/414X_opaque_ended_borrow_generic_wrapper";
    try support.expectFrontendFailure(path, "ended");
}
