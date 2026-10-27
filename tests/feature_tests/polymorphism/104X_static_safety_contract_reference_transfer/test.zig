const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/104X_static_safety_contract_reference_transfer" {
    try buildExpectFail("tests/feature_tests/polymorphism/104X_static_safety_contract_reference_transfer", "transfers requires a by-value owning input");
}
