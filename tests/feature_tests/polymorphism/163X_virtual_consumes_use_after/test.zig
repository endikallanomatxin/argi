const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/163X_virtual_consumes_use_after" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/163X_virtual_consumes_use_after", "deinitialized");
}
