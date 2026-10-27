const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/collections/81X_readonly_collection_mutation" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/collections/81X_readonly_collection_mutation", "does not satisfy contract constraint 'MutableIndexable'");
}
