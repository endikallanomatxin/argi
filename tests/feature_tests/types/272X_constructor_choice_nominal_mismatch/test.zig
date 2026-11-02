const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/272X_constructor_choice_nominal_mismatch" {
    try expectFrontendFailure("tests/feature_tests/types/272X_constructor_choice_nominal_mismatch", "no function named 'FirstWrapper'");
}
