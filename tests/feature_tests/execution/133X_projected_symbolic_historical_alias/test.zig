const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/133X_projected_symbolic_historical_alias" {
    try expectFrontendFailure("tests/feature_tests/execution/133X_projected_symbolic_historical_alias", "root that has ended");
}
