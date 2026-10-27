const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/83X_codepoints_after_text_edit" {
    try buildExpectFail("tests/feature_tests/text/83X_codepoints_after_text_edit", "ended");
}
