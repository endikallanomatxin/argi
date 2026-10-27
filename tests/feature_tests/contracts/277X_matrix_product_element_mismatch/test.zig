const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/277X_matrix_product_element_mismatch" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/277X_matrix_product_element_mismatch", "operator '*' is not defined", "pointer arithmetic");
}
