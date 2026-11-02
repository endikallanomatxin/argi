const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/74X_text_view_public_labels" {
    try expectFrontendFailure("tests/feature_tests/text/74X_text_view_public_labels", "field '_data' is private");
}
