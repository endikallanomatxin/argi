const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/234X_init_literal_shapes_ambiguous" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/234X_init_literal_shapes_ambiguous", "ambiguous Init participants");
}
