const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/266X_internal_storage_grouped_domain" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/266X_internal_storage_grouped_domain", "opaque storage effects require one mapped storage identity", "failed without a diagnostic");
}
