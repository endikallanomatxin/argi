const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/333X_text_value_nominal_identity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/333X_text_value_nominal_identity", "no function named 'accept_c_text' accepts arguments", "without a diagnostic");
}
