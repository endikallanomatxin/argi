const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/347X_bound_once_operation_reuse" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/347X_bound_once_operation_reuse", "is consumed more than once", "without a diagnostic");
}
