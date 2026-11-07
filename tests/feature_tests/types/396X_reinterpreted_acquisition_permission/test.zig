const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "types/396X_reinterpreted_acquisition_permission" {
    try support.expectFrontendFailure("tests/feature_tests/types/396X_reinterpreted_acquisition_permission", "requires an authenticated storage acquisition permission");
}
