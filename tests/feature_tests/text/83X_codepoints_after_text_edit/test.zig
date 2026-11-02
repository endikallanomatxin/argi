const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/83X_codepoints_after_text_edit" {
    try expectFrontendFailure("tests/feature_tests/text/83X_codepoints_after_text_edit", "ended");
}
