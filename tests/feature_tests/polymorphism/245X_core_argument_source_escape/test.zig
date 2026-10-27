const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/245X_core_argument_source_escape" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/245X_core_argument_source_escape", "function output cannot depend on a local storage generation", "failed without a diagnostic");
}
