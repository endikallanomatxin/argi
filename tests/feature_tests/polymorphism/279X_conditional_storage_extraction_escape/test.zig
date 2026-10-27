const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/279X_conditional_storage_extraction_escape" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/279X_conditional_storage_extraction_escape", "function output cannot depend on a local storage generation", "failed without a diagnostic");
}
