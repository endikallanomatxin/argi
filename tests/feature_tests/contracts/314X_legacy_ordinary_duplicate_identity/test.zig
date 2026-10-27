const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/314X_legacy_ordinary_duplicate_identity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/314X_legacy_ordinary_duplicate_identity", "legacy ordinary function declarations are unsupported", "panic");
}
