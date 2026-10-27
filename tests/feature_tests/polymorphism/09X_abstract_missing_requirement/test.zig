const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/09X_abstract_missing_requirement" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/09X_abstract_missing_requirement", "missing implementation operation", "panic");
}
