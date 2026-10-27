const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/87X_unicode_literal_not_choice_byte" {
    try buildExpectFail("tests/feature_tests/text/87X_unicode_literal_not_choice_byte", "Unicode scalars and bytes require explicit conversion");
}
