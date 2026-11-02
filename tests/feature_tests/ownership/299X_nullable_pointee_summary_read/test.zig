const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/299X_nullable_pointee_summary_read" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/299X_nullable_pointee_summary_read",
        "root that has ended",
    );
}
