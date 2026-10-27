const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/209X_virtual_conditional_consumption_wrong_variant" {
    try buildExpectFail("tests/feature_tests/polymorphism/209X_virtual_conditional_consumption_wrong_variant", "storage transition is not permitted");
}
