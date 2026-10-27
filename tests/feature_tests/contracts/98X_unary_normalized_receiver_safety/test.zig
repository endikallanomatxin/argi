const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/98X_unary_normalized_receiver_safety" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/98X_unary_normalized_receiver_safety", "safety contract", "panic");
}
