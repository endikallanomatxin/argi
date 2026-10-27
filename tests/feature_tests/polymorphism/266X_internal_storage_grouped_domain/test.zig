const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/266X_internal_storage_grouped_domain" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/polymorphism/266X_internal_storage_grouped_domain", "opaque storage effects require one mapped storage identity", "failed without a diagnostic");
}
