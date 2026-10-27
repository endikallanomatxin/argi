const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/318X_legacy_abstract_declaration" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/318X_legacy_abstract_declaration", "Abstract declarations are unsupported", "panic");
}
