const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/157X_selected_runtime_comptime_capture" {
    try expectFrontendFailure("tests/feature_tests/execution/157X_selected_runtime_comptime_capture", "runtime values cannot be used");
}
