const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/282X_matrix_add_shape_mismatch" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/282X_matrix_add_shape_mismatch", "operator '+' is not defined", "pointer arithmetic");
}
