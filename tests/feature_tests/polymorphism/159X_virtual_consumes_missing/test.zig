const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/159X_virtual_consumes_missing" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/159X_virtual_consumes_missing", "cannot prove consumes");
}
