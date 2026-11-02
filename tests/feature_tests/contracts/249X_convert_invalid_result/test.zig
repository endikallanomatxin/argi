const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/249X_convert_invalid_result" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/249X_convert_invalid_result", "Convert.Result must be its target participant type");
}
