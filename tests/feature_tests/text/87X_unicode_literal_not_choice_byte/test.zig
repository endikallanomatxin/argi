const support = @import("../../../support.zig");
const expectFrontendFailure = support.expectFrontendFailure;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/87X_unicode_literal_not_choice_byte" {
    try expectFrontendFailure("tests/feature_tests/text/87X_unicode_literal_not_choice_byte", "Unicode scalars and bytes require explicit conversion");
}
