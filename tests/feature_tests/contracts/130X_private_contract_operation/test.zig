const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/130X_private_contract_operation" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/130X_private_contract_operation", "private to its defining module", "panic");
}
