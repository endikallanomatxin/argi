const support = @import("../../../support.zig");
const buildExpectFail = support.buildExpectFail;

pub const isolation: support.Isolation = .fixture;

test "feature_tests/text/73X_text_view_positional" {
    try buildExpectFail("tests/feature_tests/text/73X_text_view_positional", "field '_data' is private");
}
