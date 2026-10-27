const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/182X_dormant_external_implementation" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/182X_dormant_external_implementation", "must belong to the contract module or a nominal participant module");
}
