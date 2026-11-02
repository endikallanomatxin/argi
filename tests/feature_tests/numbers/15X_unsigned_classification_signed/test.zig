const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/numbers/15X_unsigned_classification_signed" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/numbers/15X_unsigned_classification_signed", "does not satisfy contract constraint 'UInt'");
}
