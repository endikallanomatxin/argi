const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/74X_text_view_public_labels" {
    try buildExpectFail("tests/feature_tests/text/74X_text_view_public_labels", "field '_data' is private");
}
