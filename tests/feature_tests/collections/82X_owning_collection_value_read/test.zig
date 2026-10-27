const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/82X_owning_collection_value_read" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/collections/82X_owning_collection_value_read", "does not satisfy contract constraint 'IndexableValue'");
}
