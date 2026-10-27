const support = @import("../../../support.zig");
const buildExpectFailWithoutParseNoise = support.buildExpectFailWithoutParseNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/control_flow/05X_for_requires_iterator_contract" {
    try buildExpectFailWithoutParseNoise("tests/feature_tests/control_flow/05X_for_requires_iterator_contract", "for expects a type implementing contract 'Iterator', got 'FakeIterator'");
}
