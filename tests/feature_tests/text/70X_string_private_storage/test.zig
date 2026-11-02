const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/70X_string_private_storage" {
    try expectFrontendFailure("tests/feature_tests/text/70X_string_private_storage", "field '_length' is private");
}
