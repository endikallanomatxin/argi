const support = @import("../../../support.zig");
const buildExpectFailWithoutNoise = support.buildExpectFailWithoutNoise;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/13X_abstract_function_input_requires_implementation" {
    try buildExpectFailWithoutNoise("tests/feature_tests/polymorphism/13X_abstract_function_input_requires_implementation", "contract constraint 'ExampleAbstract' required by generic function parameter '.Value' of 'use_value'", "panic");
}
