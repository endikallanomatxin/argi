const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/174X_selected_associated_constraint_mismatch" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/contracts/174X_selected_associated_constraint_mismatch", "does not satisfy contract constraint 'Source'");
}
