const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/390X_symbolic_acquisition_permission_alternatives" {
    try support.expectFrontendFailure("tests/feature_tests/types/390X_symbolic_acquisition_permission_alternatives", "requires an authenticated storage acquisition permission");
}
