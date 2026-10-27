const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/180X_generic_alias_result_mismatch" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/180X_generic_alias_result_mismatch", "operation returns an incompatible associated result");
}
