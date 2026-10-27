const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/55X_virtual_method_generic" {
    try buildExpectFail("tests/feature_tests/polymorphism/55X_virtual_method_generic", "operation-local generic parameters");
}
