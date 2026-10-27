const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/25X_abstract_overloads_with_defaults_ambiguous" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/25X_abstract_overloads_with_defaults_ambiguous", "multiple applicable operation identities", "panic");
}
