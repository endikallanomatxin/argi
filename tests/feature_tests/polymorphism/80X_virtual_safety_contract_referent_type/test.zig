const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/80X_virtual_safety_contract_referent_type" {
    try buildExpectFail("tests/feature_tests/polymorphism/80X_virtual_safety_contract_referent_type", "matching input and output referent types");
}
