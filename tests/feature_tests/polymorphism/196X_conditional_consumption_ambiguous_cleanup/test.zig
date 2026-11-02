const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/196X_conditional_consumption_ambiguous_cleanup" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/196X_conditional_consumption_ambiguous_cleanup", "cannot select cleanup for conditional consumption");
}
