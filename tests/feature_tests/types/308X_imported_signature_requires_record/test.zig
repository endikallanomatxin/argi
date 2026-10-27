const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/308X_imported_signature_requires_record" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/types/308X_imported_signature_requires_record", "function input signature must be a record type", "failed without a diagnostic");
}
