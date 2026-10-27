const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/159X_concrete_selected_runtime_capture" {
    try expectFrontendFailure("tests/feature_tests/execution/159X_concrete_selected_runtime_capture", "runtime values cannot be used");
}
