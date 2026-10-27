const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/76X_virtual_safety_contract_receiver_generation" {
    try buildExpectFail("tests/feature_tests/polymorphism/76X_virtual_safety_contract_receiver_generation", "root that has ended");
}
