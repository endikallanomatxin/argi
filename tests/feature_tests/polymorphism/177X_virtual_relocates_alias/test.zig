const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/177X_virtual_relocates_alias" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/177X_virtual_relocates_alias", "alias the same storage");
}
