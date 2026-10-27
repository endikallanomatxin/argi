const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/213X_deinit_repeated_parameter" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/213X_deinit_repeated_parameter", "consumption requires an initialized owner");
}
