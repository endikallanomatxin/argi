const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/226X_virtual_relocates_inherited_consumes" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/226X_virtual_relocates_inherited_consumes", "relocates and consumes cannot target the same input");
}
