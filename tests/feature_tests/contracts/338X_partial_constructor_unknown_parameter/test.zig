const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/contracts/338X_partial_constructor_unknown_parameter" {
    try expectFrontendFailure("tests/feature_tests/contracts/338X_partial_constructor_unknown_parameter", "unknown compile-time parameter in constructor");
}
