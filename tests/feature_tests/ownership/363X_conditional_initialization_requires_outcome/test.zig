const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/363X_conditional_initialization_requires_outcome" {
    try expectFrontendFailure("tests/feature_tests/ownership/363X_conditional_initialization_requires_outcome", "cannot select cleanup for conditional initialization");
}
