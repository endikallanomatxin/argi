const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/136X_duplicate_aligned_storage_establishment" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/136X_duplicate_aligned_storage_establishment",
        "physical storage capability has already been consumed",
    );
}
