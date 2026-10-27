const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/347X_bound_once_operation_reuse" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/347X_bound_once_operation_reuse", "is consumed more than once", "without a diagnostic");
}
