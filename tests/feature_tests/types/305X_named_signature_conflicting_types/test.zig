const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/305X_named_signature_conflicting_types" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/305X_named_signature_conflicting_types", "conflicting inferred generic parameters", "failed without a diagnostic");
}
