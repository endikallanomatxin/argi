const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/289X_conditional_storage_empty_missing" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/289X_conditional_storage_empty_missing", "cannot prove empties", "failed without a diagnostic");
}
