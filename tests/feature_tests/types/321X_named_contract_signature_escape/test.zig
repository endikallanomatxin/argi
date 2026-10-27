const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/321X_named_contract_signature_escape" {
    try buildExpectFailWithoutNoise("tests/feature_tests/types/321X_named_contract_signature_escape", "root that has ended", "without a diagnostic");
}
