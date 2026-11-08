const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "424X_dynamic_acquisition_without_published_permission" {
    try support.expectFrontendFailure(
        "tests/feature_tests/types/424X_dynamic_acquisition_without_published_permission",
        "authenticated storage acquisition permission",
    );
}
