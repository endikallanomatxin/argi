const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/50X_virtual_readonly_mutable_contract" {
    try buildExpectFail("tests/feature_tests/polymorphism/50X_virtual_readonly_mutable_contract", "a mutable participant receiver requires a mutable concrete reference");
}
