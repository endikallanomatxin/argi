const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/72X_text_view_after_clear" {
    try expectFrontendFailure("tests/feature_tests/text/72X_text_view_after_clear", "ended");
}
