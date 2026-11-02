const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/213X_conditional_relocates_ambiguous" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/213X_conditional_relocates_ambiguous", "cannot select cleanup for conditional relocation");
}
