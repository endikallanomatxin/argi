const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/26X_legacy_tuple_relation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/26X_legacy_tuple_relation", "legacy conformance declarations are unsupported", "panic");
}
