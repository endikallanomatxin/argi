const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/204X_deinit_double_destruction" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/204X_deinit_double_destruction", "consumption requires an initialized owner");
}
