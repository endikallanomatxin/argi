const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/314X_generic_operation_result_mismatch" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/314X_generic_operation_result_mismatch", "operation returns an incompatible associated result", "without a diagnostic");
}
