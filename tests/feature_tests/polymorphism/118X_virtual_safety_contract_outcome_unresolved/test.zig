const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/118X_virtual_safety_contract_outcome_unresolved" {
    try buildExpectFail("tests/feature_tests/polymorphism/118X_virtual_safety_contract_outcome_unresolved", "reference depends on a root that has ended");
}
