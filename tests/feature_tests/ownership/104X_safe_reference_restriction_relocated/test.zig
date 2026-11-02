const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/104X_safe_reference_restriction_relocated" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/104X_safe_reference_restriction_relocated",
        "reference depends on a root that has ended",
    );
}
