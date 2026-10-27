const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/233X_virtual_relocates_correlated_outputs" {
    try buildExpectFail("tests/feature_tests/polymorphism/233X_virtual_relocates_correlated_outputs", "shared inputs across outputs require correlated result facts");
}
