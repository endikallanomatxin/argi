const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/85X_virtual_safety_contract_invalidate_self" {
    try buildExpectFail("tests/feature_tests/polymorphism/85X_virtual_safety_contract_invalidate_self", "invalidating an erased receiver requires a mapped storage domain");
}
