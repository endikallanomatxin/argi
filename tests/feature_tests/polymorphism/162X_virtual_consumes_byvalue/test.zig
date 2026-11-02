const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/162X_virtual_consumes_byvalue" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/162X_virtual_consumes_byvalue", "consumes requires a mutable reference input");
}
