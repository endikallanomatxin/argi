const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/146X_virtual_nested_generation_aliased_output" {
    try buildExpectFail("tests/feature_tests/polymorphism/146X_virtual_nested_generation_aliased_output", "reference depends on a root that has ended");
}
