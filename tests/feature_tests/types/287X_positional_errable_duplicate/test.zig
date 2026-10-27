const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/287X_positional_errable_duplicate" {
    try expectFrontendFailure("tests/feature_tests/types/287X_positional_errable_duplicate", "duplicate generic argument");
}
