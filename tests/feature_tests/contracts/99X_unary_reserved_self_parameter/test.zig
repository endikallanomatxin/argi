const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/99X_unary_reserved_self_parameter" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/99X_unary_reserved_self_parameter", "associated contract members cannot be named Self", "panic");
}
