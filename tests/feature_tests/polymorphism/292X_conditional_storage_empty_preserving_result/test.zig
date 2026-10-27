const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/292X_conditional_storage_empty_preserving_result" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/292X_conditional_storage_empty_preserving_result", "function output cannot depend on a local storage generation", "failed without a diagnostic");
}
