const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/201X_virtual_conditional_consumption_missing" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/201X_virtual_conditional_consumption_missing", "cannot prove consumes");
}
