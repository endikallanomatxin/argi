const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/257X_convert_fallible_wrong_target" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/257X_convert_fallible_wrong_target", "Convert.Result must be its target participant type");
}
