const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/329X_associated_family_capture_identity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/329X_associated_family_capture_identity", "distinct nominal types require explicit conversion", "without a diagnostic");
}
