const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/319X_implicit_self_contract" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/319X_implicit_self_contract", "use named participants instead of Self", "panic");
}
