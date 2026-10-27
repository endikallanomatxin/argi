const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/285X_conditional_storage_empty_unselected" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/285X_conditional_storage_empty_unselected", "function output cannot depend on a local storage generation", "failed without a diagnostic");
}
