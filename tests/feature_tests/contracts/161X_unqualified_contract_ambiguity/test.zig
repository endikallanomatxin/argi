const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/161X_unqualified_contract_ambiguity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/161X_unqualified_contract_ambiguity", "multiple applicable operation identities", "panic");
}
