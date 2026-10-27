const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/108X_virtual_safety_contract_domain_result_invalidation" {
    try buildExpectFail("tests/feature_tests/polymorphism/108X_virtual_safety_contract_domain_result_invalidation", "reference depends on a root that has ended");
}
