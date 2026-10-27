const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/343X_open_operation_identity_ambiguity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/343X_open_operation_identity_ambiguity", "multiple applicable operation identities", "without a diagnostic");
}
