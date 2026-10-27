const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/233X_virtual_relocates_correlated_outputs" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/233X_virtual_relocates_correlated_outputs", "shared inputs across outputs require correlated result facts");
}
