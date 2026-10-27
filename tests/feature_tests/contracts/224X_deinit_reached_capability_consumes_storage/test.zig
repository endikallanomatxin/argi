const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/224X_deinit_reached_capability_consumes_storage" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/224X_deinit_reached_capability_consumes_storage", "a storage transition is not permitted by this preservation contract");
}
