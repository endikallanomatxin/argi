const support = @import("../../../support.zig");
const expectFrontendFailureWithoutParseNoise = support.expectFrontendFailureWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/246X_init_reference_fields_alias" {
    try expectFrontendFailureWithoutParseNoise("tests/feature_tests/contracts/246X_init_reference_fields_alias", "consumed inputs alias the same storage");
}
