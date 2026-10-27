const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/125X_qualified_operation_argument_mismatch" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/125X_qualified_operation_argument_mismatch", "arguments do not match the selected contract operation", "panic");
}
