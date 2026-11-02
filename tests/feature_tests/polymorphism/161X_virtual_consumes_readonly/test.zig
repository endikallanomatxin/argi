const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/161X_virtual_consumes_readonly" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/161X_virtual_consumes_readonly", "consumes requires a mutable reference input");
}
