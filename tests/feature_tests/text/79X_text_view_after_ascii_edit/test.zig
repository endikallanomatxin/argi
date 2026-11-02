const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/79X_text_view_after_ascii_edit" {
    try expectFrontendFailure("tests/feature_tests/text/79X_text_view_after_ascii_edit", "ended");
}
