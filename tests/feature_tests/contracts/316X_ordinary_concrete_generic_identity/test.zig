const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/316X_ordinary_concrete_generic_identity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/316X_ordinary_concrete_generic_identity", "multiple applicable operation identities", "panic");
}
