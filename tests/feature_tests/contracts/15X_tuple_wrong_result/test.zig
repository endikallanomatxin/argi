const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/15X_tuple_wrong_result" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/15X_tuple_wrong_result", "operation returns an incompatible associated result", "panic");
}
