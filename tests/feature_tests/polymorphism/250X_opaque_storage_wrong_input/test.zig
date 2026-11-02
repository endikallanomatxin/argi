const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/250X_opaque_storage_wrong_input" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/250X_opaque_storage_wrong_input", "storage transition is not permitted", "failed without a diagnostic");
}
