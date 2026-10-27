const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/98X_unary_normalized_receiver_safety" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/98X_unary_normalized_receiver_safety", "safety contract", "panic");
}
