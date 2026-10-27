const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/53X_virtual_bound_value_mismatch" {
    try buildExpectFail("tests/feature_tests/polymorphism/53X_virtual_bound_value_mismatch", "incompatible associated elements for the virtual interface");
}
