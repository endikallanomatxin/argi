const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/308X_implement_storage_domain_alias" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/308X_implement_storage_domain_alias", "storage domains", "failed without a diagnostic");
}
