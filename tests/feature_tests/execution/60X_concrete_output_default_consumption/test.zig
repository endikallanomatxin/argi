const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/60X_concrete_output_default_consumption" {
    try expectFrontendFailure("tests/feature_tests/execution/60X_concrete_output_default_consumption", "consumption requires an initialized owner");
}
