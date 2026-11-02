const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/181X_virtual_relocates_conditional_body" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/181X_virtual_relocates_conditional_body", "cannot prove relocates");
}
