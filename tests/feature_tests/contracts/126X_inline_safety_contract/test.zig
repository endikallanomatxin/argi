const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/126X_inline_safety_contract" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/126X_inline_safety_contract", "safety contract", "panic");
}
