const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/74X_virtual_safety_contract_output_name" {
    try buildExpectFail("tests/feature_tests/polymorphism/74X_virtual_safety_contract_output_name", "the first depends_on argument must name a method output");
}
