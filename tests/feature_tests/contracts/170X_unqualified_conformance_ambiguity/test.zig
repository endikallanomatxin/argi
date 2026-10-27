const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/170X_unqualified_conformance_ambiguity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/170X_unqualified_conformance_ambiguity", "ambiguous maximal patterns", "no function named");
}
