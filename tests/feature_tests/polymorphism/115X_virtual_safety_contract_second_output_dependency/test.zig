const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/115X_virtual_safety_contract_second_output_dependency" {
    try buildExpectFail("tests/feature_tests/polymorphism/115X_virtual_safety_contract_second_output_dependency", "undeclared output dependency");
}
