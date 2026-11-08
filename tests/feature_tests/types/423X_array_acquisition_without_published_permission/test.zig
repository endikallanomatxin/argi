const support = @import("../../../support.zig");
pub const isolation: support.Isolation = .fixture;
test "423X_array_acquisition_without_published_permission" {
    try support.expectFrontendFailure(
        "tests/feature_tests/types/423X_array_acquisition_without_published_permission",
        "authenticated storage acquisition permission",
    );
}
