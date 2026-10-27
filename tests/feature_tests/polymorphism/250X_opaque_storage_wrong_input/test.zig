const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/250X_opaque_storage_wrong_input" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/250X_opaque_storage_wrong_input", "storage transition is not permitted", "failed without a diagnostic");
}
