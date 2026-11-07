const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/387X_acquisition_permission_partial_branch" {
    try support.expectFrontendFailure("tests/feature_tests/types/387X_acquisition_permission_partial_branch", "requires an authenticated storage acquisition permission");
}
