const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/278X_diagonal_product_dimension_mismatch" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/278X_diagonal_product_dimension_mismatch", "operator '*' is not defined", "pointer arithmetic");
}
