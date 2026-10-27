const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/291X_nominal_record_base_mismatch" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/types/291X_nominal_record_base_mismatch", "no function named 'accept' accepts arguments (.value: UIntNative)");
}
