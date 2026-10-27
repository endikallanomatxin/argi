const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/193X_init_legacy_collision" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/193X_init_legacy_collision", "legacy constructor declarations are unsupported; use implement Init");
}
