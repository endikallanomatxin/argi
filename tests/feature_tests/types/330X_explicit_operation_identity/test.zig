const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/330X_explicit_operation_identity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/330X_explicit_operation_identity", "multiple applicable operation identities", "without a diagnostic");
}
