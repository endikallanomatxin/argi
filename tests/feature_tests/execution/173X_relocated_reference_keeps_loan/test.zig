const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/execution/173X_relocated_reference_keeps_loan" {
    try expectFrontendFailure("tests/feature_tests/execution/173X_relocated_reference_keeps_loan", "root that has ended");
}
