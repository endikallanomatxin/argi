const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/73X_text_view_positional" {
    try expectFrontendFailure("tests/feature_tests/text/73X_text_view_positional", "field '_data' is private");
}
