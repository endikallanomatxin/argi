const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/145X_virtual_nested_generation_overwritten" {
    try buildExpectFail("tests/feature_tests/polymorphism/145X_virtual_nested_generation_overwritten", "reference depends on a root that has ended");
}
