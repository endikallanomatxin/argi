const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/132X_virtual_safety_contract_nested_variant" {
    try buildExpectFail("tests/feature_tests/polymorphism/132X_virtual_safety_contract_nested_variant", "unknown output variant");
}
