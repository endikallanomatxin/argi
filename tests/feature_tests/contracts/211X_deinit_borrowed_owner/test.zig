const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/211X_deinit_borrowed_owner" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/211X_deinit_borrowed_owner", "a storage transition is not permitted by this preservation contract");
}
