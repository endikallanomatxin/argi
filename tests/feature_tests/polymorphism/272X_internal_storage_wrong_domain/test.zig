const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/272X_internal_storage_wrong_domain" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/272X_internal_storage_wrong_domain", "storage transition is not permitted", "failed without a diagnostic");
}
