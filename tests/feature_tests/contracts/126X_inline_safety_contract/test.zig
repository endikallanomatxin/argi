const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/126X_inline_safety_contract" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/126X_inline_safety_contract", "safety contract", "panic");
}
