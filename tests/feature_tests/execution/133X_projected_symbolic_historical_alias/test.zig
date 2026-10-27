const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/133X_projected_symbolic_historical_alias" {
    try buildExpectFail("tests/feature_tests/execution/133X_projected_symbolic_historical_alias", "root that has ended");
}
