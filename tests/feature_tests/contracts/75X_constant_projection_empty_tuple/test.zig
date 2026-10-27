const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/75X_constant_projection_empty_tuple" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/75X_constant_projection_empty_tuple", "missing argument", "panic");
}
