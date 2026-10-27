const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/151X_virtual_generation_bound_exposed" {
    try buildExpectFail("tests/feature_tests/polymorphism/151X_virtual_generation_bound_exposed", "reference depends on a root that has ended");
}
