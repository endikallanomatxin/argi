const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/90X_virtual_safety_contract_domain_missing" {
    try buildExpectFail("tests/feature_tests/polymorphism/90X_virtual_safety_contract_domain_missing", "every Contract storage domain requires exactly one implementation mapping");
}
