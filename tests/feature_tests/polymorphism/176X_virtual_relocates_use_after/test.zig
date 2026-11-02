const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/176X_virtual_relocates_use_after" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/176X_virtual_relocates_use_after", "moved");
}
