const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/246X_init_reference_fields_alias" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/246X_init_reference_fields_alias", "consumed inputs alias the same storage");
}
