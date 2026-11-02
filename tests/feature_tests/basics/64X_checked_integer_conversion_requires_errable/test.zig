const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/basics/64X_checked_integer_conversion_requires_errable" {
    try expectFrontendFailure("tests/feature_tests/basics/64X_checked_integer_conversion_requires_errable", "cannot assign a fallible numeric result directly");
}
