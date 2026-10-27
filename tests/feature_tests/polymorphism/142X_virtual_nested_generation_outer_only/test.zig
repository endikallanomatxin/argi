const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/142X_virtual_nested_generation_outer_only" {
    try buildExpectFail("tests/feature_tests/polymorphism/142X_virtual_nested_generation_outer_only", "reference depends on a root that has ended");
}
