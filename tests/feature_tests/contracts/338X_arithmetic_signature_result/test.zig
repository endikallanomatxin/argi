const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/338X_arithmetic_signature_result" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/338X_arithmetic_signature_result", "arithmetic operation must return exactly (.result: Result)", "without a diagnostic");
}
