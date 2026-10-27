const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/ownership/95X_choice_unproven_payload" {
    try expectFrontendFailure(
        "tests/feature_tests/ownership/95X_choice_unproven_payload",
        "requires its variant to be proven active",
    );
}
