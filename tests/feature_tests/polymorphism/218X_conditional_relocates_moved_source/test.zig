const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/218X_conditional_relocates_moved_source" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/218X_conditional_relocates_moved_source", "moved and cannot be used");
}
