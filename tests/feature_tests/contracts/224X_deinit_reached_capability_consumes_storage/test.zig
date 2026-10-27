const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/224X_deinit_reached_capability_consumes_storage" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/224X_deinit_reached_capability_consumes_storage", "a storage transition is not permitted by this preservation contract");
}
