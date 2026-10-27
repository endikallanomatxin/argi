const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/174X_virtual_relocates_missing" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/174X_virtual_relocates_missing", "cannot prove relocates");
}
