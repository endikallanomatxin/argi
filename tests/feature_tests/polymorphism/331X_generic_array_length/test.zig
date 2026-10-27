const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/331X_generic_array_length" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/331X_generic_array_length", "array initializer has 2 elements; expected 1", "failed without a diagnostic");
}
