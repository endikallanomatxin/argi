const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/395X_local_symbolic_permission_alternatives_reversed" {
    try support.expectFrontendFailure("tests/feature_tests/types/395X_local_symbolic_permission_alternatives_reversed", "requires an authenticated storage acquisition permission");
}
