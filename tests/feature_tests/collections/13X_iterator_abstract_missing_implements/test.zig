const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/13X_iterator_abstract_missing_implements" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/collections/13X_iterator_abstract_missing_implements", "does not satisfy contract constraint 'Iterator'");
}
