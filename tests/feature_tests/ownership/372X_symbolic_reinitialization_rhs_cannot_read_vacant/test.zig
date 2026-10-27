const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/372X_symbolic_reinitialization_rhs_cannot_read_vacant" {
    try expectFrontendFailure("tests/feature_tests/ownership/372X_symbolic_reinitialization_rhs_cannot_read_vacant", "reference depends on a root that has ended");
}
