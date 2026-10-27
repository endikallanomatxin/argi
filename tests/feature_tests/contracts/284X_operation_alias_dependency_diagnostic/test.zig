const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/284X_operation_alias_dependency_diagnostic" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/284X_operation_alias_dependency_diagnostic", "invalid conformance for contract 'Required'", "the generic operation alias body could not be specialized");
}
