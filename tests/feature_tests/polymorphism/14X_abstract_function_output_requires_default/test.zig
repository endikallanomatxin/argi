const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/14X_abstract_function_output_requires_default" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/14X_abstract_function_output_requires_default", "cannot return contract 'ExampleAbstract' as a runtime value", "panic");
}
