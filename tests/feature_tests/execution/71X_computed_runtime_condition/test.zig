const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/71X_computed_runtime_condition" {
    try expectFrontendFailure("tests/feature_tests/execution/71X_computed_runtime_condition", "runtime values cannot be used");
}
