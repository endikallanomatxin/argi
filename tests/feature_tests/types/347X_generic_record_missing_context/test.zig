const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/347X_generic_record_missing_context" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/347X_generic_record_missing_context", "add an explicit type annotation", "without a diagnostic");
}
