const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/89X_constant_projection_constructor_negative_dimension" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/89X_constant_projection_constructor_negative_dimension", "array length must be non-negative", "failed without a diagnostic");
}
