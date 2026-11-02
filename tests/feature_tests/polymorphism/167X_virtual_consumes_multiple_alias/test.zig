const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/polymorphism/167X_virtual_consumes_multiple_alias" {
    try expectFrontendFailure("tests/feature_tests/polymorphism/167X_virtual_consumes_multiple_alias", "consumed inputs alias the same storage");
}
