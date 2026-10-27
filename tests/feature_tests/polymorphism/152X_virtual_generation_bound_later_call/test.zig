const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/152X_virtual_generation_bound_later_call" {
    try buildExpectFail("tests/feature_tests/polymorphism/152X_virtual_generation_bound_later_call", "reference depends on a root that has ended");
}
