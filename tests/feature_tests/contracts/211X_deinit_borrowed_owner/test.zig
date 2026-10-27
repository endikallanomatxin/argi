const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/211X_deinit_borrowed_owner" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/211X_deinit_borrowed_owner", "a storage transition is not permitted by this preservation contract");
}
