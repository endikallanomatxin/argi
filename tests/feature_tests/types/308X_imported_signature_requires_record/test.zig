const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/308X_imported_signature_requires_record" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/308X_imported_signature_requires_record", "function input signature must be a record type", "failed without a diagnostic");
}
