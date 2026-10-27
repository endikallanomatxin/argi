const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/304X_module_qualified_operation_ambiguity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/304X_module_qualified_operation_ambiguity", "multiple applicable operation identities", "failed without a diagnostic");
}
