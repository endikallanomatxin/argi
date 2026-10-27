const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/47X_tuple_result_identity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/47X_tuple_result_identity", "operation returns an incompatible associated result", "panic");
}
