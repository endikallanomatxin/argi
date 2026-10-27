const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/02X_pcg32_private_state" {
    try buildExpectFail("tests/feature_tests/numbers/02X_pcg32_private_state", "field '_state' is private to its module");
}
