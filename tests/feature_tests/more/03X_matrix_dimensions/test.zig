const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/more/03X_matrix_dimensions" {
    try buildExpectFailWithoutNoise("tests/feature_tests/more/03X_matrix_dimensions", "operator '*' is not defined", "failed without a diagnostic");
}
