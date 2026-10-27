const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/129X_external_implementation_ownership" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/129X_external_implementation_ownership", "must belong to the contract module or a nominal participant module", "panic");
}
