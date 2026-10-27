const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/16X_float_classification_integer" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/numbers/16X_float_classification_integer", "does not satisfy contract constraint 'Float'");
}
