const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/370X_symbolic_reinitialization_keeps_copy_stale" {
    try expectFrontendFailure("tests/feature_tests/ownership/370X_symbolic_reinitialization_keeps_copy_stale", "reference depends on a root that has ended");
}
