const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/156X_nested_comptime_reference_output" {
    try expectFrontendFailure("tests/feature_tests/execution/156X_nested_comptime_reference_output", "cannot return references or values requiring cleanup");
}
