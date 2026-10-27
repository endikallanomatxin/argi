const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/218X_deinit_loop_carried_aliases" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/218X_deinit_loop_carried_aliases", "consumption requires an initialized owner");
}
