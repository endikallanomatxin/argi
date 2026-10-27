const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/351X_operation_expression_value" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/351X_operation_expression_value", "implementation operation must be a compile-time function definition value", "without a diagnostic");
}
