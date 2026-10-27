const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/135X_generic_implementation_result" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/135X_generic_implementation_result", "incompatible associated result", "panic");
}
