const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/198X_conditional_consumption_aliased_owners" {
    try buildExpectFail("tests/feature_tests/polymorphism/198X_conditional_consumption_aliased_owners", "consumed inputs alias the same storage");
}
