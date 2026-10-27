const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/339X_runtime_array_dimension" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/339X_runtime_array_dimension", "runtime values cannot be used", "failed without a diagnostic");
}
