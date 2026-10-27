const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/131X_private_operation_alias" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/131X_private_operation_alias", "unknown or inaccessible implementation function", "panic");
}
