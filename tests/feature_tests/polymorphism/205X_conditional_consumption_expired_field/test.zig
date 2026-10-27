const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/205X_conditional_consumption_expired_field" {
    try buildExpectFail("tests/feature_tests/polymorphism/205X_conditional_consumption_expired_field", "root that has ended");
}
