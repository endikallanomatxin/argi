const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/374X_symbolic_call_reinitialization_keeps_alias_stale" {
    try expectFrontendFailure("tests/feature_tests/ownership/374X_symbolic_call_reinitialization_keeps_alias_stale", "reference depends on a root that has ended");
}
