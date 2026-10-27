const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/modules/26X_module_qualified_operation_ambiguity" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/modules/26X_module_qualified_operation_ambiguity", "multiple applicable operation identities", "panic");
}
