const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/81X_virtual_safety_contract_referent_mutability" {
    try buildExpectFail("tests/feature_tests/polymorphism/81X_virtual_safety_contract_referent_mutability", "cannot grant mutable access");
}
