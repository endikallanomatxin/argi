const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/79X_virtual_safety_contract_referent_branch" {
    try buildExpectFail("tests/feature_tests/polymorphism/79X_virtual_safety_contract_referent_branch", "cannot prove refers_to");
}
