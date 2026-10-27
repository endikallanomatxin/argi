const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/315X_virtual_generic_contract_operation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/315X_virtual_generic_contract_operation", "generic contract operations require static specialization and cannot be virtualized", "without a diagnostic");
}
