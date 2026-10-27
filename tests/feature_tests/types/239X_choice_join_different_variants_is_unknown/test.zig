const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/239X_choice_join_different_variants_is_unknown" {
    try expectFrontendFailure(
        "tests/feature_tests/types/239X_choice_join_different_variants_is_unknown",
        "choice payload '..0' requires its variant to be proven active",
    );
}
