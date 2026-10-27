const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/15X_unsigned_classification_signed" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/numbers/15X_unsigned_classification_signed", "does not satisfy contract constraint 'UInt'");
}
