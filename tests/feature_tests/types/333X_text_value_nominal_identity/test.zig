const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/333X_text_value_nominal_identity" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/types/333X_text_value_nominal_identity", "no function named 'accept_c_text' accepts arguments", "without a diagnostic");
}
