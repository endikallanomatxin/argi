const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/types/288X_positional_errable_excess" {
    try expectFrontendFailure("tests/feature_tests/types/288X_positional_errable_excess", "too many generic arguments");
}
