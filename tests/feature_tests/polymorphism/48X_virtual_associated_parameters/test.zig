const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/48X_virtual_associated_parameters" {
    try buildExpectFail("tests/feature_tests/polymorphism/48X_virtual_associated_parameters", "incompatible associated elements for the virtual interface");
}
