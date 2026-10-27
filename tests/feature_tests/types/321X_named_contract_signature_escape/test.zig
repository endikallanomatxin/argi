const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/321X_named_contract_signature_escape" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/types/321X_named_contract_signature_escape", "root that has ended", "without a diagnostic");
}
