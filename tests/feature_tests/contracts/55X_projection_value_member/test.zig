const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/55X_projection_value_member" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/55X_projection_value_member", "associated element is not a type", "panic");
}
