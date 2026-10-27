const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/356X_generic_scalar_output_signature" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/356X_generic_scalar_output_signature", "function output signature must be a record type", "failed without a diagnostic");
}
