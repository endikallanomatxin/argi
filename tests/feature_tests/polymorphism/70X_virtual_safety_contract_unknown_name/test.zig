const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/70X_virtual_safety_contract_unknown_name" {
    try buildExpectFail("tests/feature_tests/polymorphism/70X_virtual_safety_contract_unknown_name", "depends_on dependencies must name method inputs");
}
