const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/272X_internal_storage_wrong_domain" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/272X_internal_storage_wrong_domain", "storage transition is not permitted", "failed without a diagnostic");
}
