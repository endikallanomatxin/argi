const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/103X_static_safety_contract_readonly" {
    try buildExpectFail("tests/feature_tests/polymorphism/103X_static_safety_contract_readonly", "invalidates requires a mutable reference input");
}
