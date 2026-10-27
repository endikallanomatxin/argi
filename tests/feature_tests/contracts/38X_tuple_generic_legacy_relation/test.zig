const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/38X_tuple_generic_legacy_relation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/38X_tuple_generic_legacy_relation", "legacy conformance declarations are unsupported", "panic");
}
