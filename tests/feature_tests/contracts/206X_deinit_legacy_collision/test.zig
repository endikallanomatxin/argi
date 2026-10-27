const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/206X_deinit_legacy_collision" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/206X_deinit_legacy_collision", "legacy destructor declarations are unsupported; use implement Deinit");
}
