const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/72X_constant_projection_negative_dimension" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/72X_constant_projection_negative_dimension", "array length must be non-negative", "panic");
}
