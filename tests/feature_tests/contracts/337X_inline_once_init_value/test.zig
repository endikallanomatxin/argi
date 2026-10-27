const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/337X_inline_once_init_value" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/337X_inline_once_init_value", "is consumed more than once", "without a diagnostic");
}
