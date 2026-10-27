const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/105X_virtual_safety_contract_undeclared_owner" {
    try buildExpectFail("tests/feature_tests/polymorphism/105X_virtual_safety_contract_undeclared_owner", "undeclared fresh output ownership");
}
