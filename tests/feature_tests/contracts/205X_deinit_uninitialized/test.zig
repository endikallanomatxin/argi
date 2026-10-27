const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/205X_deinit_uninitialized" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/205X_deinit_uninitialized", "consumption requires an initialized owner");
}
