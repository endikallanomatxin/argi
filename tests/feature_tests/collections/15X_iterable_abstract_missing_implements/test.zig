const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/15X_iterable_abstract_missing_implements" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/collections/15X_iterable_abstract_missing_implements", "does not satisfy contract constraint 'Iterable'");
}
