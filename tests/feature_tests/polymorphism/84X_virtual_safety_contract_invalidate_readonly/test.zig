const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/84X_virtual_safety_contract_invalidate_readonly" {
    try buildExpectFail("tests/feature_tests/polymorphism/84X_virtual_safety_contract_invalidate_readonly", "invalidates requires a mutable reference input");
}
