const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/195X_conditional_consumption_unselected_cleanup" {
    try buildExpectFail("tests/feature_tests/polymorphism/195X_conditional_consumption_unselected_cleanup", "cannot select cleanup for conditional consumption");
}
