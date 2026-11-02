const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/282X_matrix_add_shape_mismatch" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/282X_matrix_add_shape_mismatch", "operator '+' is not defined", "pointer arithmetic");
}
