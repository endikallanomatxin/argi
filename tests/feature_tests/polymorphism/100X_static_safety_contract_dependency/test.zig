const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/100X_static_safety_contract_dependency" {
    try buildExpectFail("tests/feature_tests/polymorphism/100X_static_safety_contract_dependency", "undeclared output dependency");
}
