const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/255X_generic_unknown_argument" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/255X_generic_unknown_argument", "unknown compile-time argument in call to 'identity'");
}
