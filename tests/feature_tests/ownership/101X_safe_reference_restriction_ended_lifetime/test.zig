const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/101X_safe_reference_restriction_ended_lifetime" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/101X_safe_reference_restriction_ended_lifetime",
        "reference depends on a root that has ended",
    );
}
