const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/224X_conditional_relocates_scope_reference" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/224X_conditional_relocates_scope_reference", "reference depends on a root that has ended");
}
