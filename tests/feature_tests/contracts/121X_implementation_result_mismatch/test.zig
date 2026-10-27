const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/121X_implementation_result_mismatch" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/121X_implementation_result_mismatch", "operation returns an incompatible associated result", "panic");
}
