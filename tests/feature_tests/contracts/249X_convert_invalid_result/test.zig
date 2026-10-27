const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/249X_convert_invalid_result" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/249X_convert_invalid_result", "Convert.Result must be its target participant type");
}
