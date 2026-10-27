const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/53X_projection_wrong_argument" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/53X_projection_wrong_argument", "unknown argument name", "panic");
}
