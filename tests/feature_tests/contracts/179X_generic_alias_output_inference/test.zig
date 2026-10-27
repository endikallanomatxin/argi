const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/179X_generic_alias_output_inference" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/179X_generic_alias_output_inference", "parameters must be inferred from the selected input signature");
}
