const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/295X_independent_record_contract" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/types/295X_independent_record_contract", "does not satisfy contract constraint 'Marked'");
}
