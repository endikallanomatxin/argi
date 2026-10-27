const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/202X_conditional_consumption_use_after" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/202X_conditional_consumption_use_after", "deinitialized");
}
