const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/272X_equal_argument_shapes_ambiguous" {
    try expectFrontendFailure("tests/feature_tests/contracts/272X_equal_argument_shapes_ambiguous", "ambiguous conformances for the same participant tuple");
}
