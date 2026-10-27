const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/332X_generic_array_element" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/332X_generic_array_element", "integer literal 256 does not fit in 'UInt8'", "failed without a diagnostic");
}
