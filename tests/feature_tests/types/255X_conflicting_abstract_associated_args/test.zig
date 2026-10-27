const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/255X_conflicting_abstract_associated_args" {
    try expectFrontendFailure(
        "tests/feature_tests/types/255X_conflicting_abstract_associated_args",
        "ambiguous conformances for the same participant tuple",
    );
}
