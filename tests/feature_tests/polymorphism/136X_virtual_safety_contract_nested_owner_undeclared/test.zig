const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/136X_virtual_safety_contract_nested_owner_undeclared" {
    try buildExpectFail("tests/feature_tests/polymorphism/136X_virtual_safety_contract_nested_owner_undeclared", "undeclared fresh output ownership");
}
