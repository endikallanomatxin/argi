const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/184X_generic_alias_unsatisfied_bound" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/184X_generic_alias_unsatisfied_bound", "does not satisfy the generic operation alias bounds");
}
