const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/89X_virtual_safety_contract_domain_overlap" {
    try buildExpectFail("tests/feature_tests/polymorphism/89X_virtual_safety_contract_domain_overlap", "storage domains overlap");
}
