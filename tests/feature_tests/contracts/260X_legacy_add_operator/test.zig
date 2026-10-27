const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/260X_legacy_add_operator" {
    try buildExpectFail("tests/feature_tests/contracts/260X_legacy_add_operator", "operator + declarations are unsupported; use implement Add");
}
