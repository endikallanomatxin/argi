const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/156X_virtual_generation_bound_early_return" {
    try buildExpectFail("tests/feature_tests/polymorphism/156X_virtual_generation_bound_early_return", "reference depends on a root that has ended");
}
