const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .exclusive;

test "feature_tests/modules/26X_module_qualified_operation_ambiguity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/modules/26X_module_qualified_operation_ambiguity", "multiple applicable operation identities", "panic");
}
