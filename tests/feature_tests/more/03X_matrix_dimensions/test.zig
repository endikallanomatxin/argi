const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/more/03X_matrix_dimensions" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/more/03X_matrix_dimensions", "operator '*' is not defined", "failed without a diagnostic");
}
