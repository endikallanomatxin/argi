const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/301X_generic_choice_payload_out_of_range" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/301X_generic_choice_payload_out_of_range", "integer literal 256 does not fit in 'UInt8'", "failed without a diagnostic");
}
