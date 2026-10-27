const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/113X_virtual_safety_contract_scalar_selector" {
    try buildExpectFail("tests/feature_tests/polymorphism/113X_virtual_safety_contract_scalar_selector", "on requires a choice-valued output");
}
