const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/338X_arithmetic_signature_result" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/338X_arithmetic_signature_result", "arithmetic operation must return exactly (.result: Result)", "without a diagnostic");
}
