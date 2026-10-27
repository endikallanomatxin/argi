const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/315X_legacy_ordinary_compiletime_identity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/315X_legacy_ordinary_compiletime_identity", "legacy ordinary function declarations are unsupported", "panic");
}
