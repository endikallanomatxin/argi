const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/335X_family_integer_parameter_type" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/335X_family_integer_parameter_type", "type-family argument does not match its parameter signature", "failed without a diagnostic");
}
