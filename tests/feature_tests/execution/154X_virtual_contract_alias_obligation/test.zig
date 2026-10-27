const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/execution/154X_virtual_contract_alias_obligation" {
    try buildExpectFail("tests/feature_tests/execution/154X_virtual_contract_alias_obligation", "a caller-side storage alias obligation is not represented by this contract");
}
