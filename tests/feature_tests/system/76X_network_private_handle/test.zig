const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/system/76X_network_private_handle" {
    try expectFrontendFailure("tests/feature_tests/system/76X_network_private_handle", "field '_handle' is private");
}
