const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/256X_legacy_numeric_type_call" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/256X_legacy_numeric_type_call", "numeric type-call conversions are unsupported; use convert");
}
