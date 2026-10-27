const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/23X_explicit_self" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/23X_explicit_self", "use named participants instead of Self", "panic");
}
