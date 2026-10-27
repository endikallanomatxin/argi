const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/122X_implementation_input_mismatch" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/122X_implementation_input_mismatch", "incompatible input signature", "panic");
}
