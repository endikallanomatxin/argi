const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/143X_virtual_nested_generation_preservation" {
    try buildExpectFail("tests/feature_tests/polymorphism/143X_virtual_nested_generation_preservation", "a storage transition is not permitted");
}
