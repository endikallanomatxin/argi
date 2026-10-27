const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/16X_float_classification_integer" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/numbers/16X_float_classification_integer", "does not satisfy contract constraint 'Float'");
}
