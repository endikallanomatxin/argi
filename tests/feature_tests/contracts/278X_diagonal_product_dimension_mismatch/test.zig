const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/278X_diagonal_product_dimension_mismatch" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/278X_diagonal_product_dimension_mismatch", "operator '*' is not defined", "pointer arithmetic");
}
