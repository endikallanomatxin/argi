const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/82X_owning_collection_value_read" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/collections/82X_owning_collection_value_read", "does not satisfy contract constraint 'IndexableValue'");
}
