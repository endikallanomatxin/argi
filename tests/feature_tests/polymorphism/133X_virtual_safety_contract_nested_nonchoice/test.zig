const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/133X_virtual_safety_contract_nested_nonchoice" {
    try buildExpectFail("tests/feature_tests/polymorphism/133X_virtual_safety_contract_nested_nonchoice", "choice-valued output payload");
}
