const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/12X_abstract_instantiation_missing_default" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/12X_abstract_instantiation_missing_default", "contract 'ExampleAbstract' has no runtime representation", "panic");
}
