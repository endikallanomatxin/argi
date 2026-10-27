const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/290X_nominal_record_mismatch" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/types/290X_nominal_record_mismatch", "no function named 'accept' accepts arguments (.value: EdgeId)");
}
