const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/268X_legacy_equal_operator" {
    try buildExpectFail("tests/feature_tests/contracts/268X_legacy_equal_operator", "comparison operator declarations are unsupported; use implement Equal");
}
