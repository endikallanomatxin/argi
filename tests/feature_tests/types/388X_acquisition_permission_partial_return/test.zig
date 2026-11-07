const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/388X_acquisition_permission_partial_return" {
    try support.expectFrontendFailure("tests/feature_tests/types/388X_acquisition_permission_partial_return", "requires an authenticated storage acquisition permission");
}
