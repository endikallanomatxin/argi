const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/202X_conditional_consumption_use_after" {
    try buildExpectFail("tests/feature_tests/polymorphism/202X_conditional_consumption_use_after", "deinitialized");
}
