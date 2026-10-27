const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/83X_virtual_safety_contract_invalidate_alias" {
    try buildExpectFail("tests/feature_tests/polymorphism/83X_virtual_safety_contract_invalidate_alias", "root that has ended");
}
