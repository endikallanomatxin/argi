const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/216X_deinit_parameter_overwrite" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/216X_deinit_parameter_overwrite", "consumption requires an initialized owner");
}
