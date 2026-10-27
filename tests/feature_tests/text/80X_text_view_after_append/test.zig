const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/80X_text_view_after_append" {
    try buildExpectFail("tests/feature_tests/text/80X_text_view_after_append", "ended");
}
