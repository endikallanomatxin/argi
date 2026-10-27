const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/164X_unqualified_generic_ordinary_ambiguity" {
    try buildExpectFailWithoutNoise("tests/feature_tests/contracts/164X_unqualified_generic_ordinary_ambiguity", "multiple applicable operation identities", "panic");
}
