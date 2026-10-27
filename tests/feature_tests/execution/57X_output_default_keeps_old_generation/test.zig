const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/57X_output_default_keeps_old_generation" {
    try expectFrontendFailure("tests/feature_tests/execution/57X_output_default_keeps_old_generation", "reference depends on a root that has ended");
}
