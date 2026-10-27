const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/282X_conditional_storage_inherited_identity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/282X_conditional_storage_inherited_identity", "from_storage cannot be combined with exact transfers for the same output", "failed without a diagnostic");
}
