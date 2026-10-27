const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/207X_deinit_result" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/207X_deinit_result", "operation returns an incompatible associated result");
}
