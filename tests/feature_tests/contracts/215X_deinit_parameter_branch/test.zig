const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/215X_deinit_parameter_branch" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/215X_deinit_parameter_branch", "consumption requires an initialized owner");
}
