const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/python/06X_private_handle" {
    try expectFrontendFailure("tests/feature_tests/python/06X_private_handle", "field '_handle' is private to its module");
}
