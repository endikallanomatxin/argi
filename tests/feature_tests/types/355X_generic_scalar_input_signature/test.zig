const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/355X_generic_scalar_input_signature" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/355X_generic_scalar_input_signature", "arguments do not match this specialized function definition", "failed without a diagnostic");
}
