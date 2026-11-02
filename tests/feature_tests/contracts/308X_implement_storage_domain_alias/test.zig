const support = @import("../../../support.zig");
const expectFrontendFailureWithoutNoise = support.expectFrontendFailureWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/308X_implement_storage_domain_alias" {
    try expectFrontendFailureWithoutNoise("tests/feature_tests/contracts/308X_implement_storage_domain_alias", "storage domains", "failed without a diagnostic");
}
