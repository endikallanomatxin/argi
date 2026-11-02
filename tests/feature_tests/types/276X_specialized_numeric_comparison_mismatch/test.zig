const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/276X_specialized_numeric_comparison_mismatch" {
    try expectFrontendFailure("tests/feature_tests/types/276X_specialized_numeric_comparison_mismatch", "no conformance for the qualified operation's participants");
}
