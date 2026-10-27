const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/114X_generic_inaccessible_global" {
    try expectFrontendFailure("tests/feature_tests/execution/114X_generic_inaccessible_global", "unknown name 'foreign_value' in this scope");
}
