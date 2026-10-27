const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/110X_virtual_safety_contract_missing" {
    try buildExpectFail("tests/feature_tests/polymorphism/110X_virtual_safety_contract_missing", "virtual methods require a declared safety contract");
}
