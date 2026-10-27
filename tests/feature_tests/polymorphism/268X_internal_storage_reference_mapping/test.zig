const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/268X_internal_storage_reference_mapping" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/268X_internal_storage_reference_mapping", "opaque storage domain mappings cannot select reference fields", "failed without a diagnostic");
}
