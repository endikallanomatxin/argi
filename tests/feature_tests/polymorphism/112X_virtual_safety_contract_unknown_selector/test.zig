const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/112X_virtual_safety_contract_unknown_selector" {
    try buildExpectFail("tests/feature_tests/polymorphism/112X_virtual_safety_contract_unknown_selector", "on must select a named method input or output");
}
