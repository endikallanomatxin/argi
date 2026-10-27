const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/40X_defer_hash_prefix" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/control_flow/40X_defer_hash_prefix", "use 'defer' without a '#' prefix");
}
