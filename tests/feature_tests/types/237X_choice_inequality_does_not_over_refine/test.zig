const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/237X_choice_inequality_does_not_over_refine" {
    try expectFrontendFailure(
        "tests/feature_tests/types/237X_choice_inequality_does_not_over_refine",
        "choice payload '..0' is not active",
    );
}
