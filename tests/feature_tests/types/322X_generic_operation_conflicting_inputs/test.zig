const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/322X_generic_operation_conflicting_inputs" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/322X_generic_operation_conflicting_inputs", "conflicting inferred generic parameters in call to 'pair'", "without a diagnostic");
}
