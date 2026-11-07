const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/392X_wrapped_acquisition_permission_alternatives" {
    try support.expectFrontendFailure("tests/feature_tests/types/392X_wrapped_acquisition_permission_alternatives", "requires an authenticated storage acquisition permission");
}
