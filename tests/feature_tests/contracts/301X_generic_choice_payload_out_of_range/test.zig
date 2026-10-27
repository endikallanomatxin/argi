const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/301X_generic_choice_payload_out_of_range" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/301X_generic_choice_payload_out_of_range", "integer literal 256 does not fit in 'UInt8'", "failed without a diagnostic");
}
