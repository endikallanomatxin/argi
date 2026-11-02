const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;
const vmExpect = support.vmExpect;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/194X_symbolic_replacement_keeps_historical_alias" {
    try buildExpectFail("tests/feature_tests/execution/194X_symbolic_replacement_keeps_historical_alias", "root that has ended");
    try vmExpect("tests/feature_tests/execution/194X_symbolic_replacement_keeps_historical_alias", 1, "root that has ended");
}
