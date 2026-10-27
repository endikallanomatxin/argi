const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/325X_type_family_signature_mismatch" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/325X_type_family_signature_mismatch", "type-family argument does not match its parameter signature", "without a diagnostic");
}
