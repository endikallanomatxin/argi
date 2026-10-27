const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/130X_private_contract_operation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/130X_private_contract_operation", "private to its defining module", "panic");
}
