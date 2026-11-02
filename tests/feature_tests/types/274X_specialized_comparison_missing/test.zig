const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/274X_specialized_comparison_missing" {
    try expectFrontendFailure("tests/feature_tests/types/274X_specialized_comparison_missing", "no conformance for the qualified operation's participants");
}
